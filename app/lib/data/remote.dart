import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/env.dart';
import 'models.dart';

/// Supabase REST(PostgREST) 읽기 전용 클라이언트.
///
/// anon 키만 쓴다. 쓰기는 RLS 가 막아 두었고 앱은 쓸 일이 없다.
/// supabase_flutter 패키지를 쓰지 않는 이유는, 필요한 게 GET 네 개뿐이라
/// 인증·실시간·스토리지까지 들여올 까닭이 없어서다.
class Remote {
  Remote({http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  bool get isConfigured => Env.hasBackend;

  Uri _uri(String path, Map<String, String> query) =>
      Uri.parse('${Env.supabaseUrl}/rest/v1/$path').replace(
        queryParameters: query,
      );

  Map<String, String> get _headers => {
        'apikey': Env.supabaseAnonKey,
        'Authorization': 'Bearer ${Env.supabaseAnonKey}',
        'Accept': 'application/json',
      };

  Future<List<dynamic>> _get(String path, Map<String, String> query) async {
    final res = await _client.get(_uri(path, query), headers: _headers)
        .timeout(timeout);
    if (res.statusCode >= 400) {
      throw RemoteException('$path HTTP ${res.statusCode}', res.body);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
  }

  /// 서버 쪽 데이터 버전. 이것만 보고 내려받을지 정한다.
  Future<int> dataVersion() async {
    final rows = await _get('data_version', {'select': 'version', 'limit': '1'});
    if (rows.isEmpty) return 0;
    return (rows.first as Map<String, dynamic>)['version'] as int;
  }

  /// 전체 데이터. 200KB 남짓이라 델타 없이 통째로 받는다.
  ///
  /// 폐지된 행도 함께 받는다. 사용자가 저장한 항목이 폐지됐을 때
  /// "폐지됨" 을 보여줘야 하기 때문이다.
  Future<AppData> fetchAll() async {
    final results = await Future.wait([
      dataVersion(),
      _get('sources',
          {'select': 'slug,byeolpyo_label,title,amended,notes,source_url,'
              'law_name,enforce_date'}),
      _get('concepts', {
        'select': 'key,title,summary,category,subcategory,'
            'awareness_score,audience',
        'order': 'awareness_score.desc,key',
      }),
      _get('violations', {
        'select': 'id,concept,category,zone,source_slug,ref,action,parent_action,'
            'legal_basis,penalty_formula,confirmed_by,repealed_at,repealed_reason,'
            'violation_penalties(kind,vehicle_type,offense_count,'
            'amount_krw,surcharge_krw)',
      }),
    ]);

    final version = results[0] as int;
    final sources = results[1] as List<dynamic>;
    final concepts = results[2] as List<dynamic>;
    final violations = results[3] as List<dynamic>;

    // 법령 이름·시행일은 sources 에 있다. 빠뜨리면 상세 화면의
    // "시행일" 줄과 홈 부제가 사라진다.
    final first = sources.isEmpty ? null : sources.first as Map<String, dynamic>;

    return AppData.fromJson({
      'version': version,
      'law': {
        'name': first?['law_name'] ?? '도로교통법 시행령',
        'enforce_date': first?['enforce_date'],
      },
      'sources': [
        for (final s in sources.cast<Map<String, dynamic>>())
          {
            'slug': s['slug'],
            'label': s['byeolpyo_label'],
            'title': s['title'],
            'amended': s['amended'],
            'notes': s['notes'],
            'url': s['source_url'],
            'law': s['law_name'],
            'enforce': s['enforce_date'],
          },
      ],
      'concepts': [
        for (final c in concepts.cast<Map<String, dynamic>>())
          {
            'key': c['key'],
            'title': c['title'],
            'summary': c['summary'],
            'sub': c['subcategory'],
            'score': c['awareness_score'],
            'audience': c['audience'],
            'cat': c['category'],
          },
      ],
      'violations': [
        for (final v in violations.cast<Map<String, dynamic>>())
          {
            'id': v['id'],
            'concept': v['concept'],
            'cat': v['category'],
            'zone': v['zone'],
            'source': v['source_slug'],
            'ref': v['ref'],
            'action': v['action'],
            'parent': v['parent_action'],
            'basis': v['legal_basis'],
            'formula': v['penalty_formula'],
            'confirmed': v['confirmed_by'],
            'repealed_at': v['repealed_at'],
            'repealed_reason': v['repealed_reason'],
            'penalties': [
              for (final p
                  in (v['violation_penalties'] as List? ?? const [])
                      .cast<Map<String, dynamic>>())
                {
                  'kind': p['kind'],
                  'veh': p['vehicle_type'],
                  'amt': p['amount_krw'],
                  'n': p['offense_count'],
                  'sur': p['surcharge_krw'],
                },
            ],
          },
      ],
    });
  }

  /// 검수를 마쳐 게시된 법령 변경만. RLS 가 published=false 를 걸러 준다.
  Future<List<LawChange>> fetchChanges() async {
    final rows = await _get('law_changes', {
      'select': 'id,change_type,title,body,enforce_date,source_url',
      'order': 'enforce_date.asc.nullslast,created_at.desc',
      'limit': '50',
    });
    return [
      for (final r in rows.cast<Map<String, dynamic>>()) LawChange.fromJson(r),
    ];
  }

  /// FCM 토큰 등록. devices 테이블에 직접 쓰지 않고 함수를 부른다.
  ///
  /// anon 에게 devices UPDATE 를 열어 주면 남의 등록을 고칠 수 있어,
  /// register_device() 하나만 실행 권한을 줬다 (0001_init.sql).
  Future<void> registerDevice(
      String token, String platform, List<String> topics) async {
    final res = await _client.post(
      Uri.parse('${Env.supabaseUrl}/rest/v1/rpc/register_device'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'p_token': token,
        'p_platform': platform == 'iOS' ? 'ios' : 'android',
        'p_topics': topics,
      }),
    ).timeout(timeout);
    if (res.statusCode >= 400) {
      throw RemoteException('register_device HTTP ${res.statusCode}', res.body);
    }
  }

  void close() => _client.close();
}

class RemoteException implements Exception {
  RemoteException(this.message, [this.detail]);
  final String message;
  final String? detail;

  @override
  String toString() => 'RemoteException: $message';
}
