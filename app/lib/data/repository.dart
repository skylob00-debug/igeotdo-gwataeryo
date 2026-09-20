import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'remote.dart';

/// 데이터 한 곳.
///
/// 오프라인 우선이다. 순서는 이렇다.
///   1. 앱에 번들된 assets/seed.json 을 먼저 띄운다 (네트워크 없이 바로 동작)
///   2. 예전에 받아 둔 캐시가 더 새것이면 그것으로 바꾼다
///   3. 뒤에서 서버 data_version 을 확인해 올라갔을 때만 내려받는다
///
/// 지금 데이터가 200KB 남짓이라 SQLite 를 쓰지 않는다. 통째로 메모리에 두고
/// 캐시는 JSON 파일 하나다. 생활 과태료(Phase 2)로 자료가 크게 늘면
/// 이 클래스 안만 바꿔 끼우면 된다.
class Repository {
  Repository({Remote? remote}) : _remote = remote ?? Remote();

  static const _seedAsset = 'assets/seed.json';
  static const _cacheFile = 'data.json';

  /// 캐시가 담고 있는 자료의 '모양' 판.
  ///
  /// data_version 은 서버 자료가 몇 번째인지만 말한다. 앱이 읽는 필드가
  /// 늘어나면(예: 갈래 cat, 위반 횟수 n) 같은 버전의 옛 캐시에는 그 필드가
  /// 없는데, 버전이 같으니 sync 가 다시 받지도 않는다. 실제로 생활 과태료를
  /// 붙인 뒤 이 일이 났다 — 캐시에 cat 이 없어 모든 개념이 driving 으로
  /// 읽혔고 생활 탭이 비었다.
  ///
  /// 모델(models.dart)이나 _toJson 이 바뀌면 이 번호를 올린다.
  /// 올리면 옛 캐시는 버려지고 번들 seed 로 시작한 뒤 서버에서 다시 받는다.
  static const _cacheSchema = 2;
  static const _savedKey = 'saved_concepts';
  static const _consentKey = 'disclaimer_version';

  /// 면책 고지 판. 문구가 실질적으로 바뀌면 올린다. 그러면 다시 한 번 뜬다.
  static const consentVersion = 1;

  final Remote _remote;

  AppData? _data;
  SharedPreferences? _prefs;

  AppData get data => _data ?? (throw StateError('load() 를 먼저 부르세요'));

  /// 화면을 띄우기 전에 한 번. 네트워크를 기다리지 않는다.
  Future<AppData> load() async {
    _prefs = await SharedPreferences.getInstance();
    final seed = await _readSeed();
    final cached = await _readCache();
    _data = (cached != null && cached.version > seed.version) ? cached : seed;
    return _data!;
  }

  Future<AppData> _readSeed() async {
    final text = await rootBundle.loadString(_seedAsset);
    return AppData.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<File> _cachePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_cacheFile');
  }

  Future<AppData?> _readCache() async {
    try {
      final file = await _cachePath();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // 모양이 다른 캐시는 버린다. 필드가 없는 채로 읽으면 기본값으로
      // 조용히 대체돼, 화면에서 항목이 통째로 사라지는 식으로 드러난다.
      if (json['schema'] != _cacheSchema) return null;
      return AppData.fromJson(json);
    } catch (_) {
      return null; // 깨진 캐시는 없는 셈 친다. seed 가 항상 있으니 안전하다.
    }
  }

  /// 서버가 더 새것일 때만 내려받는다. 실패해도 앱은 그대로 돈다.
  ///
  /// 반환: 갱신했으면 true.
  Future<bool> sync() async {
    if (!_remote.isConfigured) return false;
    try {
      final serverVersion = await _remote.dataVersion();
      if (_data != null && serverVersion <= _data!.version) return false;

      final fresh = await _remote.fetchAll();
      _data = fresh;
      final file = await _cachePath();
      await file.writeAsString(jsonEncode(_toJson(fresh)));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// FCM 토큰을 서버에 등록한다. Push 가 불러 준다.
  Future<void> registerDevice(
      String token, String platform, List<String> topics) async {
    if (!_remote.isConfigured) return;
    await _remote.registerDevice(token, platform, topics);
  }

  Future<List<LawChange>> changes() async {
    if (!_remote.isConfigured) return const [];
    try {
      return await _remote.fetchChanges();
    } catch (_) {
      return const [];
    }
  }

  // --- 면책 고지 동의 --------------------------------------------------------
  // 기기에만 남긴다. 계정이 없으므로 서버로 보내지 않는다.

  bool get hasConsented =>
      (_prefs?.getInt(_consentKey) ?? 0) >= consentVersion;

  Future<void> acceptConsent() async =>
      _prefs?.setInt(_consentKey, consentVersion);

  // --- 저장 (즐겨찾기) ------------------------------------------------------
  // 기기에만 둔다. 계정이 없으므로 서버로 보내지 않는다.

  Set<String> get saved =>
      (_prefs?.getStringList(_savedKey) ?? const <String>[]).toSet();

  bool isSaved(String conceptKey) => saved.contains(conceptKey);

  Future<Set<String>> toggleSaved(String conceptKey) async {
    final next = saved;
    if (!next.remove(conceptKey)) next.add(conceptKey);
    await _prefs?.setStringList(_savedKey, next.toList());
    return next;
  }

  Map<String, dynamic> _toJson(AppData d) => {
        'schema': _cacheSchema,
        'version': d.version,
        'law': {'name': d.lawName, 'enforce_date': d.enforceDate},
        'sources': [
          for (final s in d.sources)
            {
              'slug': s.slug,
              'label': s.label,
              'title': s.title,
              'amended': s.amended,
              'notes': s.notes,
              'url': s.url,
              'law': s.lawName,
              'enforce': s.enforceDate?.toIso8601String().split('T').first,
            },
        ],
        'concepts': [
          for (final c in d.concepts)
            {
              'key': c.key,
              'title': c.title,
              'summary': c.summary,
              'sub': c.subcategory,
              'score': c.score,
              'audience': c.audience,
              'cat': c.category,
            },
        ],
        'violations': [
          for (final v in d.violations)
            {
              'id': v.id,
              'concept': v.conceptKey,
              'cat': v.category,
              'zone': v.zone.code,
              'source': v.sourceSlug,
              'ref': v.ref,
              'action': v.action,
              'parent': v.parentAction,
              'basis': v.basis,
              'formula': v.formula,
              'confirmed': v.confirmedBy,
              'repealed_at': v.repealedAt?.toIso8601String().split('T').first,
              'repealed_reason': v.repealedReason,
              'penalties': [
                for (final p in v.penalties)
                  {
                    'kind': p.kind.code,
                    'veh': p.vehicle.code,
                    'amt': p.amount,
                    'n': p.offenseCount,
                    'sur': p.surcharge,
                  },
              ],
            },
        ],
      };
}

/// 개념 목록을 걸러내고 정렬하는 규칙. 화면 여러 곳에서 쓴다.
abstract final class Feed {
  /// 홈 피드. 고른 갈래에서 나와 상관있고 현행인 것만, 몰랐을 가능성 순.
  ///
  /// audience 를 거르지 않으면 대상이 아닌 항목이 상위를 덮는다.
  /// 운전 갈래에서는 학원 운영자 조항이, 생활 갈래에서는 폐기물처리업자
  /// 조항이 그렇다. 모른다는 것과 나와 상관있다는 것은 다른 축이다.
  static List<Concept> home(AppData data,
      {String category = 'driving', String? subcategory}) {
    final list = data.concepts
        .where((c) => c.category == category)
        .where((c) => c.isForHome)
        .where((c) => !data.isConceptRepealed(c.key))
        .where((c) => subcategory == null || c.subcategory == subcategory)
        .toList();
    list.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.key.compareTo(b.key);
    });
    return list;
  }

  /// 검색어와 대상에서 똑같이 걷어내는 것들.
  ///
  /// 띄어쓰기와 가운뎃점을 지운다. 법령 표기는 '신호·지시 위반' 인데
  /// 사용자는 '신호 지시' 라고 친다. 가운뎃점은 원천마다 코드포인트가
  /// 달라서(· ㆍ ・) 어차피 한 번 정리해야 한다.
  static final _noise = RegExp(r'[\s·ㆍ・,]');

  static String _norm(String s) => _noise.allMatches(s).isEmpty
      ? s
      : s.replaceAll(_noise, '');

  /// 검색. 제목·설명·분류와 별표 원문·근거 조문까지 본다.
  /// 폐지된 것도 찾을 수 있어야 한다 ("예전엔 과태료였는데?").
  static List<Concept> search(AppData data, String query) {
    final q = _norm(query.trim());
    if (q.isEmpty) return const [];

    bool hit(Concept c) {
      final haystack = StringBuffer()
        ..write(c.title)
        ..write(c.summary)
        ..write(c.subcategory);
      for (final v in data.forConcept(c.key)) {
        haystack
          ..write(v.action)
          ..write(v.parentAction ?? '')
          ..write(v.basis)
          ..write(v.ref);
      }
      return _norm(haystack.toString()).contains(q);
    }

    final list = data.concepts.where(hit).toList();
    list.sort((a, b) {
      // 제목에 걸린 것을 위로
      final at = _norm(a.title).contains(q) ? 0 : 1;
      final bt = _norm(b.title).contains(q) ? 0 : 1;
      if (at != bt) return at - bt;
      return b.score.compareTo(a.score);
    });
    return list;
  }

  /// 홈 필터 칩에 쓸 분류. 개념이 많은 순. 갈래 안에서만 센다.
  static List<String> subcategories(AppData data,
      {String category = 'driving'}) {
    final count = <String, int>{};
    for (final c in data.concepts
        .where((c) => c.category == category && c.isForHome)) {
      count[c.subcategory] = (count[c.subcategory] ?? 0) + 1;
    }
    final keys = count.keys.toList()
      ..sort((a, b) => count[b]!.compareTo(count[a]!));
    return keys;
  }
}
