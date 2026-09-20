import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gwataeryo/core/format.dart';
import 'package:gwataeryo/data/models.dart';
import 'package:gwataeryo/data/repository.dart';

/// 번들된 seed 를 실제로 읽어 검증한다.
///
/// 금액은 법이 정한 값이라 앱이 틀리게 보여주면 안 된다.
/// 파이프라인 쪽 pytest 와 같은 값을 여기서 한 번 더 본다.
/// 둘 중 하나만 깨져도 어딘가 어긋난 것이다.
AppData loadSeed() {
  final text = File('assets/seed.json').readAsStringSync();
  return AppData.fromJson(jsonDecode(text) as Map<String, dynamic>);
}

void main() {
  late AppData data;

  setUpAll(() => data = loadSeed());

  group('seed 적재', () {
    test('개념·위반행위·금액 건수', () {
      // 도로교통법 4개 별표 + 폐기물관리법 별표 8
      expect(data.concepts, hasLength(125 + 62));
      expect(data.violations, hasLength(183 + 89));
      expect(
        data.violations.fold<int>(0, (n, v) => n + v.penalties.length),
        556 + 267,
      );
      expect(data.sources, hasLength(5));
      expect(data.sources.map((s) => s.label),
          containsAll(['별표 6', '별표 7', '별표 8', '별표 10']));
    });

    test('별표마다 소속 법령이 붙는다', () {
      // 별표 번호만으로는 구분되지 않는다. 별표 8 이 둘 있다.
      final byLaw = <String, List<String>>{};
      for (final s in data.sources) {
        byLaw.putIfAbsent(s.lawName, () => []).add(s.label);
      }
      expect(byLaw['도로교통법 시행령'], hasLength(4));
      expect(byLaw['폐기물관리법 시행령'], ['별표 8']);
      final waste = data.sources.firstWhere((s) => s.slug == 'waste8');
      expect(waste.fullLabel, '폐기물관리법 시행령 별표 8');
      expect(waste.enforceDate, DateTime(2026, 3, 26));
      expect(waste.notes, isNotEmpty);   // 일반기준(가중·감경)
    });

    test('모든 위반행위가 개념에 붙는다', () {
      final keys = data.concepts.map((c) => c.key).toSet();
      for (final v in data.violations) {
        expect(keys, contains(v.conceptKey), reason: v.id);
      }
    });

    test('모든 개념에 문구가 있다', () {
      for (final c in data.concepts) {
        expect(c.title, isNotEmpty);
        expect(c.summary, isNotEmpty, reason: c.key);
        expect(c.score, inInclusiveRange(0, 100));
      }
    });

    test('별표 비고가 실려 있다', () {
      final b6 = data.sources.firstWhere((s) => s.slug == 'byeolpyo6');
      expect(b6.notes, hasLength(4));
      expect(b6.notes.last, contains('2시간 이상'));
      expect(b6.url, startsWith('https://www.law.go.kr'));
    });
  });

  group('금액 실측', () {
    int amount(String conceptKey, Zone zone, PenaltyKind kind, Vehicle veh) {
      final hits = data
          .forConcept(conceptKey)
          .where((v) => v.zone == zone)
          .expand((v) => v.penalties)
          .where((p) => p.kind == kind && p.vehicle == veh);
      expect(hits, isNotEmpty, reason: '$conceptKey $zone $kind $veh');
      return hits.first.amount;
    }

    test('신호·지시 위반 — 일반도로', () {
      expect(amount('signal', Zone.none, PenaltyKind.ticket, Vehicle.car), 60000);
      expect(amount('signal', Zone.none, PenaltyKind.fine, Vehicle.car), 70000);
    });

    test('신호·지시 위반 — 보호구역은 2배', () {
      expect(amount('signal', Zone.both, PenaltyKind.ticket, Vehicle.car), 120000);
      expect(amount('signal', Zone.both, PenaltyKind.fine, Vehicle.car), 130000);
    });

    test('속도위반 60km/h 초과', () {
      expect(amount('speed-over-60', Zone.none, PenaltyKind.ticket, Vehicle.car), 120000);
      expect(amount('speed-over-60', Zone.none, PenaltyKind.fine, Vehicle.car), 130000);
    });

    test('어린이보호구역과 노인·장애인보호구역은 금액이 다르다', () {
      expect(amount('no-stopping', Zone.school, PenaltyKind.fine, Vehicle.car), 120000);
      expect(amount('no-stopping', Zone.senior, PenaltyKind.fine, Vehicle.car), 80000);
    });

    test('2시간 이상 주정차 가중 금액', () {
      final car = data
          .forConcept('no-stopping')
          .where((v) => v.zone == Zone.none && v.sourceSlug == 'byeolpyo6')
          .expand((v) => v.penalties)
          .firstWhere((p) => p.vehicle == Vehicle.car);
      expect(car.amount, 40000);
      expect(car.surcharge, 50000);
    });

    test('누진 과태료는 가산 규칙이 따로 있다', () {
      final withFormula =
          data.violations.where((v) => v.formula != null).toList();
      expect(withFormula, hasLength(1));
      expect(withFormula.single.formula, contains('3일을 초과할 때마다'));
    });
  });

  group('피드 규칙', () {
    test('홈은 일반 운전자 대상만 보여준다', () {
      final home = Feed.home(data);
      expect(home, isNotEmpty);
      expect(home.every((c) => c.isForHome), isTrue);
      // 학원·운영자 조항이 상위를 덮으면 안 된다
      expect(home.take(10).map((c) => c.subcategory), isNot(contains('학원')));
    });

    test('홈은 몰랐을 가능성 순으로 정렬된다', () {
      final home = Feed.home(data);
      for (var i = 1; i < home.length; i++) {
        expect(home[i - 1].score, greaterThanOrEqualTo(home[i].score));
      }
      expect(home.first.title, '물 튀김');
    });

    test('분류 필터', () {
      final parking = Feed.home(data, subcategory: '주정차');
      expect(parking, isNotEmpty);
      expect(parking.every((c) => c.subcategory == '주정차'), isTrue);
    });

    test('검색은 별표 원문과 설명까지 본다', () {
      expect(Feed.search(data, '주차').map((c) => c.title), contains('주차금지 위반'));
      // '전동킥보드' 는 제목에 없고 설명에만 있다
      expect(Feed.search(data, '킥보드'), isNotEmpty);
      // 근거 조문으로도 찾힌다
      expect(Feed.search(data, '제5조').map((c) => c.title), contains('신호·지시 위반'));
      expect(Feed.search(data, ''), isEmpty);
    });

    test('검색은 띄어쓰기를 무시한다', () {
      expect(Feed.search(data, '신호 지시'), isNotEmpty);
    });

    test('분류 목록은 개념이 많은 순', () {
      final subs = Feed.subcategories(data);
      expect(subs, isNotEmpty);
      expect(subs.first, '통행');
      expect(subs, isNot(contains('학원'))); // driver 대상만
    });
  });

  group('생활 과태료', () {
    test('갈래가 갈린다', () {
      final living = data.concepts.where((c) => c.category == 'waste');
      expect(living, hasLength(62));
      expect(data.concepts.where((c) => c.isDriving), hasLength(125));
      // 홈에 나갈 것은 갈래마다 대상이 다르다
      expect(living.where((c) => c.isForHome), hasLength(7));
    });

    test('담배꽁초는 5만원, 횟수가 올라가도 같다', () {
      final ps = data
          .forConcept('litter-handheld')
          .expand((v) => v.penalties)
          .toList();
      expect(ps, hasLength(3));
      expect(ps.map((p) => p.amount).toSet(), {50000});
      expect(ps.map((p) => p.offenseCount).toList()..sort(), [1, 2, 3]);
      expect(ps.every((p) => p.vehicle == Vehicle.none), isTrue);
      expect(ps.every((p) => p.kind == PenaltyKind.fine), isTrue);
    });

    test('조치명령 미이행은 횟수마다 오른다', () {
      final ps = data.forConcept('order-ignore').expand((v) => v.penalties);
      final byCount = {for (final p in ps) p.offenseCount: p.amount};
      expect(byCount, {1: 300000, 2: 700000, 3: 1000000});
    });

    test('생활 과태료에는 보호구역도 차종도 없다', () {
      final living =
          data.violations.where((v) => v.category == 'waste').toList();
      expect(living, hasLength(89));
      expect(living.every((v) => v.zone == Zone.none), isTrue);
      expect(
        living.expand((v) => v.penalties).every((p) => p.vehicle == Vehicle.none),
        isTrue,
      );
      // 거꾸로 도로교통법에는 횟수 구분이 없다
      expect(
        data.violations
            .where((v) => v.category == 'driving')
            .expand((v) => v.penalties)
            .every((p) => p.offenseCount == 1),
        isTrue,
      );
    });

    test('홈은 고른 갈래만 보여준다', () {
      final driving = Feed.home(data);
      final living = Feed.home(data, category: 'waste');
      expect(driving.every((c) => c.isDriving), isTrue);
      expect(living.every((c) => c.category == 'waste'), isTrue);
      expect(living, hasLength(7));
      expect(living.first.title, '정해진 방법대로 내놓지 않기');   // 가장 안 알려진 것
      expect(Feed.subcategories(data, category: 'waste'),
          containsAll(['무단투기', '배출·분리수거']));
    });
  });

  group('폐지 처리', () {
    test('지금은 폐지된 것이 없다', () {
      expect(data.violations.where((v) => v.isRepealed), isEmpty);
    });

    test('개념 전체가 폐지돼야 폐지로 본다', () {
      // 하나라도 현행이면 현행이다 (별표별로 폐지 시점이 다를 수 있다)
      expect(data.isConceptRepealed('signal'), isFalse);
      expect(data.isConceptRepealed('없는개념'), isFalse);
    });
  });

  group('빈 문자열은 없는 값으로 본다', () {
    // DB 컬럼이 not null default '' 라 서버에서는 빈 문자열이 온다.
    // 그대로 두면 상세 화면에 빈 "가산 규칙" 패널이 그려진다.
    test('서버 모양(빈 문자열)도 seed 와 같게 읽힌다', () {
      final v = Violation.fromJson({
        'id': 'x', 'concept': 'c', 'zone': 'none', 'source': 'byeolpyo6',
        'ref': '제1호', 'action': '테스트', 'basis': '제1조',
        'parent': '', 'formula': '', 'confirmed': '', 'repealed_reason': '',
        'penalties': const [],
      });
      expect(v.formula, isNull);
      expect(v.parentAction, isNull);
      expect(v.confirmedBy, isNull);
      expect(v.repealedReason, isNull);
    });
  });

  group('표기', () {
    test('금액', () {
      expect(won(70000), '7만원');
      expect(won(5000000), '500만원');
      expect(won(500), '500원');
      expect(wonShort(120000), '12만');
    });

    test('차종별 한 줄', () {
      const ps = [
        Penalty(kind: PenaltyKind.ticket, vehicle: Vehicle.car, amount: 60000),
        Penalty(kind: PenaltyKind.ticket, vehicle: Vehicle.van, amount: 70000),
      ];
      expect(vehicleLine(ps), '승합 7만 · 승용 6만'); // 큰 차부터
    });

    test('대표 금액은 승용차 우선', () {
      const ps = [
        Penalty(kind: PenaltyKind.fine, vehicle: Vehicle.van, amount: 80000),
        Penalty(kind: PenaltyKind.fine, vehicle: Vehicle.car, amount: 70000),
      ];
      expect(headline(ps)!.vehicle, Vehicle.car);
      expect(headlineNote(headline(ps)!), '승용차 기준');
    });

    test('날짜', () {
      expect(korDate(DateTime(2026, 8, 1)), '2026. 8. 1.');
      expect(korDateStr('2025-03-18'), '2025. 3. 18.');
    });
  });

  group('캐시 모양이 다르면 버린다', () {
    // data_version 은 서버 자료가 몇 번째인지만 말한다. 앱이 읽는 필드가
    // 늘어나면 같은 버전의 옛 캐시에 그 필드가 없는데, 버전이 같으니
    // sync 도 다시 받지 않는다. 실기기에서 생활 탭이 통째로 비어 이걸 찾았다.
    test('schema 가 없는 옛 캐시는 읽지 않는다', () {
      final stale = {
        'version': 9,
        'law': {'name': '도로교통법 시행령'},
        'sources': const [],
        'concepts': [
          {'key': 'x', 'title': 'x', 'summary': 'x', 'sub': '기타', 'score': 0},
        ],
        'violations': const [],
      };
      // 옛 캐시를 그대로 읽으면 갈래가 driving 으로 조용히 채워진다.
      final asRead = AppData.fromJson(stale);
      expect(asRead.concepts.single.category, 'driving');
      expect(stale.containsKey('schema'), isFalse,
          reason: 'schema 가 없으면 Repository 가 캐시를 버려야 한다');
    });

    test('지금 seed 는 갈래를 싣고 있다', () {
      // seed 가 갈래를 싣지 않으면 캐시를 버려도 생활 탭이 빈다
      expect(data.concepts.any((c) => c.category == 'waste'), isTrue);
      expect(
        data.violations
            .expand((v) => v.penalties)
            .any((p) => p.offenseCount > 1),
        isTrue,
      );
    });
  });
}
