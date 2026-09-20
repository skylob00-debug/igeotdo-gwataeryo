/// 앱이 다루는 자료형.
///
/// 모양은 pipeline/export_seed.py 가 만드는 seed.json 과 같다.
/// 서버(Supabase)에서 갱신해 받을 때도 같은 모양으로 맞춘다.
library;

/// 빈 문자열을 null 로 본다.
///
/// DB 컬럼이 `not null default ''` 라 서버에서는 빈 문자열이 오고,
/// seed 에서는 아예 빠진다. 둘을 같게 다루지 않으면 "가산 규칙" 같은
/// 빈 칸이 화면에 그려진다.
String? _text(Object? v) {
  final s = v as String?;
  return (s == null || s.trim().isEmpty) ? null : s;
}

/// 부과 종류.
enum PenaltyKind {
  fine('fine', '과태료'),
  ticket('ticket', '범칙금');

  const PenaltyKind(this.code, this.label);
  final String code;
  final String label;

  static PenaltyKind from(String code) =>
      values.firstWhere((k) => k.code == code, orElse: () => fine);
}

/// 보호구역 구분. 별표 7·10 의 목이 곧 이 구분이다.
enum Zone {
  none('none', '일반도로'),
  school('school', '어린이보호구역'),
  senior('senior', '노인·장애인보호구역'),
  both('both', '보호구역');

  const Zone(this.code, this.label);
  final String code;
  final String label;

  bool get isProtected => this != Zone.none;

  static Zone from(String code) =>
      values.firstWhere((z) => z.code == code, orElse: () => none);
}

/// 차종. 별표 비고의 정의를 따른다.
enum Vehicle {
  van('van', '승합', '승합차·4톤 초과 화물차·특수차·건설기계·노면전차'),
  car('car', '승용', '승용차·4톤 이하 화물차'),
  motorcycle('motorcycle', '이륜', '이륜차·원동기장치자전거(개인형 이동장치 제외)'),
  bicycle('bicycle', '자전거', '자전거등 및 손수레등'),
  pm('pm', 'PM', '개인형 이동장치'),
  all('all', '전차종', '차종 구분 없음'),
  // 생활 과태료에는 차종이 없다. 'all'(모든 차마)과 뜻이 다르므로 값을 따로 둔다.
  none('none', '', '차종 구분 없음');

  const Vehicle(this.code, this.label, this.note);
  final String code;
  final String label;
  final String note;

  /// 표에 쓰는 순서. 큰 차부터.
  int get order => index;

  static Vehicle from(String code) =>
      values.firstWhere((v) => v.code == code, orElse: () => all);
}

class Penalty {
  const Penalty({
    required this.kind,
    required this.vehicle,
    required this.amount,
    this.surcharge,
    this.offenseCount = 1,
  });

  final PenaltyKind kind;
  final Vehicle vehicle;
  final int amount;

  /// 같은 장소에서 2시간 이상 정차·주차 위반 시 적용되는 가중 금액.
  /// 별표 6·7 비고에 정의돼 있다.
  final int? surcharge;

  /// 위반 횟수(1·2·3차 이상). 생활 과태료는 횟수마다 금액이 다르다.
  /// 도로교통법 별표에는 구분이 없어 전부 1 이다.
  final int offenseCount;

  /// '1차' '2차' '3차 이상'. 횟수 구분이 없으면 빈 값.
  String get offenseLabel => switch (offenseCount) {
        2 => '2차',
        3 => '3차 이상',
        _ => '1차',
      };

  factory Penalty.fromJson(Map<String, dynamic> j) => Penalty(
        kind: PenaltyKind.from(j['kind'] as String),
        vehicle: Vehicle.from(j['veh'] as String),
        amount: j['amt'] as int,
        surcharge: j['sur'] as int?,
        offenseCount: (j['n'] as int?) ?? 1,
      );
}

/// 별표의 부과 단위 한 줄.
class Violation {
  const Violation({
    required this.id,
    required this.conceptKey,
    required this.zone,
    required this.sourceSlug,
    this.category = 'driving',
    required this.ref,
    required this.action,
    required this.basis,
    required this.penalties,
    this.parentAction,
    this.formula,
    this.confirmedBy,
    this.repealedAt,
    this.repealedReason,
  });

  final String id;
  final String conceptKey;

  /// driving / waste / etc. 개념 쪽과 같은 값이다.
  final String category;
  final Zone zone;
  final String sourceSlug;

  /// '제4의2호 가목'
  final String ref;

  /// 별표 원문. 법문 그대로라 상세 화면에서 인용으로만 보여준다.
  final String action;
  final String? parentAction;
  final String basis;

  /// 정수 하나로 표현되지 않는 누진 과태료의 가산 규칙.
  final String? formula;

  /// 자동으로 못 풀어 사람이 확정한 경우 그 근거.
  final String? confirmedBy;

  /// 폐지일. null 이면 현행. 폐지돼도 지우지 않는 이유는
  /// 사용자가 저장한 항목이 말없이 사라지면 안 되기 때문이다.
  final DateTime? repealedAt;
  final String? repealedReason;

  final List<Penalty> penalties;

  bool get isRepealed => repealedAt != null;

  PenaltyKind get kind =>
      penalties.isEmpty ? PenaltyKind.fine : penalties.first.kind;

  factory Violation.fromJson(Map<String, dynamic> j) => Violation(
        id: j['id'] as String,
        conceptKey: j['concept'] as String,
        category: _text(j['cat']) ?? 'driving',
        zone: Zone.from(j['zone'] as String),
        sourceSlug: j['source'] as String,
        ref: j['ref'] as String,
        action: j['action'] as String,
        parentAction: _text(j['parent']),
        basis: j['basis'] as String,
        formula: _text(j['formula']),
        confirmedBy: _text(j['confirmed']),
        repealedAt: j['repealed_at'] == null
            ? null
            : DateTime.parse(j['repealed_at'] as String),
        repealedReason: _text(j['repealed_reason']),
        penalties: [
          for (final p in (j['penalties'] as List? ?? const []))
            Penalty.fromJson(p as Map<String, dynamic>),
        ],
      );
}

/// 위반 개념. 앱 카드 하나에 대응한다.
///
/// 같은 위반이 별표에서 최대 네 번 나온다 (과태료/범칙금 x 일반/보호구역).
/// 개념으로 묶어 카드 하나에 표로 보여준다.
class Concept {
  const Concept({
    required this.key,
    required this.title,
    required this.summary,
    required this.subcategory,
    required this.score,
    required this.audience,
    required this.category,
  });

  final String key;
  final String title;
  final String summary;
  final String subcategory;

  /// '몰랐을 가능성' 0~100. 홈 정렬에 쓴다. 화면에는 보여주지 않는다.
  final int score;

  /// driver / operator / academy / resident.
  final String audience;

  /// driving / waste / etc. 홈 상단 탭이 이 값으로 갈린다.
  final String category;

  bool get isDriving => category == 'driving';

  /// 홈 피드에 낼 것인가. 갈래마다 대상이 다르다.
  ///   운전 -> 일반 운전자, 생활 -> 생활인
  /// 나머지(사업자·학원·처리업체)는 검색으로만 닿는다.
  bool get isForHome =>
      isDriving ? audience == 'driver' : audience == 'resident';


  factory Concept.fromJson(Map<String, dynamic> j) => Concept(
        key: j['key'] as String,
        title: j['title'] as String,
        summary: _text(j['summary']) ?? '',
        subcategory: (j['sub'] as String?) ?? '기타',
        score: (j['score'] as int?) ?? 0,
        audience: (j['audience'] as String?) ?? 'driver',
        category: (j['cat'] as String?) ?? 'driving',
      );
}

/// 별표 단위 출처. 앱 면책 표기의 근거다.
class Source {
  const Source({
    required this.slug,
    required this.label,
    required this.title,
    required this.notes,
    required this.url,
    required this.lawName,
    this.amended,
    this.enforceDate,
  });

  final String slug;

  /// '별표 8'
  final String label;
  final String title;

  /// 별표 머리말의 개정일. '2025. 6. 2.'
  final String? amended;

  /// 별표 비고. 차종 정의와 2시간 가중 조건이 여기 있어 반드시 보여줘야 한다.
  final List<String> notes;
  final String url;

  /// 이 별표가 속한 법령. '도로교통법 시행령' / '폐기물관리법 시행령'
  ///
  /// 법령이 둘 이상이라 출처마다 따로 둔다. 별표 번호만으로는 구분되지 않는다
  /// (도로교통법 별표 8 과 폐기물관리법 별표 8 이 둘 다 있다).
  final String lawName;

  /// 이 별표가 속한 법령의 시행일.
  final DateTime? enforceDate;

  /// '폐기물관리법 시행령 별표 8'
  String get fullLabel => '$lawName $label';

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        slug: j['slug'] as String,
        label: j['label'] as String,
        title: j['title'] as String,
        amended: _text(j['amended']),
        notes: [for (final n in (j['notes'] as List? ?? const [])) n as String],
        url: j['url'] as String,
        lawName: _text(j['law']) ?? '도로교통법 시행령',
        enforceDate: _text(j['enforce']) == null
            ? null
            : DateTime.parse(j['enforce'] as String),
      );
}

/// 법령 변경 알림. 서버에서만 받는다 (seed 에는 없다).
class LawChange {
  const LawChange({
    required this.id,
    required this.changeType,
    required this.title,
    required this.body,
    this.enforceDate,
    this.sourceUrl,
  });

  final int id;

  /// amended / upcoming / byeolpyo_changed
  final String changeType;
  final String title;
  final String body;
  final DateTime? enforceDate;
  final String? sourceUrl;

  String get typeLabel => switch (changeType) {
        'upcoming' => '시행 예정',
        'byeolpyo_changed' => '금액 변경',
        _ => '개정',
      };

  factory LawChange.fromJson(Map<String, dynamic> j) => LawChange(
        id: j['id'] as int,
        changeType: j['change_type'] as String,
        title: j['title'] as String,
        body: (j['body'] as String?) ?? '',
        enforceDate: j['enforce_date'] == null
            ? null
            : DateTime.parse(j['enforce_date'] as String),
        sourceUrl: j['source_url'] as String?,
      );
}

/// 앱이 들고 있는 데이터 한 벌.
class AppData {
  AppData({
    required this.version,
    required this.lawName,
    required this.enforceDate,
    required this.sources,
    required this.concepts,
    required this.violations,
  })  : _sourceBySlug = {for (final s in sources) s.slug: s},
        _byConcept = _group(violations);

  final int version;
  final String lawName;
  final String? enforceDate;
  final List<Source> sources;
  final List<Concept> concepts;
  final List<Violation> violations;

  final Map<String, Source> _sourceBySlug;
  final Map<String, List<Violation>> _byConcept;

  static Map<String, List<Violation>> _group(List<Violation> vs) {
    final m = <String, List<Violation>>{};
    for (final v in vs) {
      (m[v.conceptKey] ??= []).add(v);
    }
    return m;
  }

  Source? source(String slug) => _sourceBySlug[slug];

  List<Violation> forConcept(String key) => _byConcept[key] ?? const [];

  /// 카드 전체가 폐지된 개념인가. 하나라도 현행이면 현행으로 본다.
  bool isConceptRepealed(String key) {
    final vs = forConcept(key);
    return vs.isNotEmpty && vs.every((v) => v.isRepealed);
  }

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        version: (j['version'] as int?) ?? 0,
        lawName: (j['law']?['name'] as String?) ?? '도로교통법 시행령',
        enforceDate: j['law']?['enforce_date'] as String?,
        sources: [
          for (final s in (j['sources'] as List? ?? const []))
            Source.fromJson(s as Map<String, dynamic>),
        ],
        concepts: [
          for (final c in (j['concepts'] as List? ?? const []))
            Concept.fromJson(c as Map<String, dynamic>),
        ],
        violations: [
          for (final v in (j['violations'] as List? ?? const []))
            Violation.fromJson(v as Map<String, dynamic>),
        ],
      );
}
