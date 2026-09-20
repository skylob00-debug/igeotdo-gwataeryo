import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gwataeryo/core/theme.dart';
import 'package:gwataeryo/data/providers.dart';
import 'package:gwataeryo/data/repository.dart';
import 'package:gwataeryo/features/consent_page.dart';
import 'package:gwataeryo/features/detail_page.dart';
import 'package:gwataeryo/features/home_page.dart';
import 'package:gwataeryo/features/saved_page.dart';
import 'package:gwataeryo/features/search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 화면이 실제로 그려지는지 본다.
///
/// 빌드가 된다고 화면이 뜨는 건 아니다. 오버플로나 null 참조는 여기서만 잡힌다.
/// 실기기 없이 확인할 수 있는 마지막 관문이다.
Future<Repository> makeRepo({bool consented = false}) async {
  SharedPreferences.setMockInitialValues(
      consented ? {'disclaimer_version': Repository.consentVersion} : {});
  final repo = Repository();
  await repo.load();
  return repo;
}

/// 테스트 화면을 폰 크기로. 기본 800x600 이면 ListView 가 아래쪽을
/// 만들지 않아 "없다" 는 오판이 난다.
void usePhone(WidgetTester tester, {Size size = const Size(390, 844)}) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// 목록 안에 있는 것을 찾을 때까지 굴린다.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Widget wrap(Repository repo, Widget child) => ProviderScope(
      overrides: [repositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Repository repo;

  setUp(() async => repo = await makeRepo());

  testWidgets('홈 — 카드가 그려지고 가장 위는 물 튀김', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(repo, const HomePage()));
    await tester.pumpAndSettle();

    expect(find.text('몰랐다가 무는 과태료'), findsOneWidget);
    expect(find.text('물 튀김'), findsOneWidget);
    expect(find.text('전체'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('홈 — 분류 칩으로 거른다', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(repo, const HomePage()));
    await tester.pumpAndSettle();

    // 칩 줄은 가로로 스크롤된다
    await tester.dragUntilVisible(find.text('주정차'),
        find.byType(ListView).first, const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('주정차'));
    await tester.pumpAndSettle();

    expect(find.text('물 튀김'), findsNothing); // 운전 중 행위라 걸러진다
    expect(find.text('경사진 곳 정차·주차방법 위반'), findsOneWidget);
  });

  testWidgets('상세 — 일반도로와 보호구역 금액이 한 표에', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(repo, const DetailPage(conceptKey: 'signal')));
    await tester.pumpAndSettle();

    expect(find.text('신호·지시 위반'), findsOneWidget);
    expect(find.text('일반도로'), findsOneWidget);
    expect(find.text('보호구역'), findsOneWidget);
    expect(find.text('약 2배'), findsOneWidget);

    // 과태료와 범칙금 둘 다 나온다
    expect(find.text('과태료'), findsWidgets);
    expect(find.text('범칙금'), findsWidgets);

    // 금액을 보여주는 화면에는 면책이 반드시 있어야 한다
    await scrollTo(tester, find.textContaining('법적 효력이 없습니다'));
    expect(find.textContaining('법적 효력이 없습니다'), findsOneWidget);
    expect(find.textContaining('책임지지 않습니다'), findsOneWidget);
    expect(find.textContaining('국가법령정보센터'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('상세 — 근거 조문과 시행일이 나온다', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(repo, const DetailPage(conceptKey: 'signal')));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.textContaining('2026. 8. 1.'));
    expect(find.textContaining('제5조'), findsWidgets);
    expect(find.textContaining('2026. 8. 1.'), findsWidgets);
    expect(find.textContaining('별표'), findsWidgets);
  });

  testWidgets('상세 — 2시간 가중 금액이 표에 보인다', (tester) async {
    usePhone(tester);
    await tester
        .pumpWidget(wrap(repo, const DetailPage(conceptKey: 'no-stopping')));
    await tester.pumpAndSettle();

    expect(find.textContaining('2시간'), findsWidgets);
    expect(find.text('어린이보호구역'), findsOneWidget);
    expect(find.text('노인·장애인보호구역'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('검색 — 낱말을 치면 결과가 나온다', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(repo, const SearchPage()));
    await tester.pumpAndSettle();

    expect(find.text('이렇게도 찾아보세요'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '킥보드');
    await tester.pumpAndSettle();

    expect(find.textContaining('개인형 이동장치'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('검색 — 없는 낱말', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(repo, const SearchPage()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '우주선');
    await tester.pumpAndSettle();

    expect(find.text('찾는 규정이 없습니다'), findsOneWidget);
  });

  testWidgets('저장 — 비었을 때와 담았을 때', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(repo, const SavedPage()));
    await tester.pumpAndSettle();
    expect(find.text('저장한 규정이 없습니다'), findsOneWidget);

    await repo.toggleSaved('signal');
    await tester.pumpWidget(const SizedBox()); // 트리를 버리고 다시 만든다
    await tester.pumpWidget(wrap(repo, const SavedPage()));
    await tester.pumpAndSettle();
    expect(find.text('신호·지시 위반'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('저장 토글이 상세 화면에서 동작한다', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(repo, const DetailPage(conceptKey: 'signal')));
    await tester.pumpAndSettle();

    expect(repo.isSaved('signal'), isFalse);
    await tester.tap(find.byTooltip('저장'));
    await tester.pumpAndSettle();
    expect(repo.isSaved('signal'), isTrue);
  });

  testWidgets('좁은 화면에서도 넘치지 않는다', (tester) async {
    usePhone(tester, size: const Size(320, 640));

    await tester.pumpWidget(wrap(repo, const HomePage()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(wrap(repo, const DetailPage(conceptKey: 'signal')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('최초 실행 면책 고지', () {
    testWidgets('처음이면 뜨고, 확인을 누르면 다시 뜨지 않는다', (tester) async {
      usePhone(tester);
      var accepted = false;
      await tester.pumpWidget(wrap(
        repo,
        ConsentPage(onAccept: () async {
          await repo.acceptConsent();
          accepted = true;
        }),
      ));
      await tester.pumpAndSettle();

      expect(repo.hasConsented, isFalse);
      expect(find.text('이것도 과태료?'), findsOneWidget);
      expect(find.text('법적 효력은 없습니다'), findsOneWidget);
      expect(find.textContaining('책임지지 않습니다'), findsWidgets);

      await tester.tap(find.text('확인했습니다'));
      await tester.pumpAndSettle();

      expect(accepted, isTrue);
      expect(repo.hasConsented, isTrue);
    });

    // 아래 둘은 testWidgets 가 아니라 test 다. testWidgets 는 가짜 비동기
    // 구역에서 돌아 Repository.load() 의 번들 읽기가 끝나지 않는다.
    // (실제로 여기서 한 번 멈췄다)
    test('이미 동의했으면 다시 묻지 않는다', () async {
      final done = await makeRepo(consented: true);
      expect(done.hasConsented, isTrue);
    });

    test('문구 판이 올라가면 다시 묻는다', () async {
      final old = await makeRepo();
      expect(old.hasConsented, isFalse);
      await old.acceptConsent();
      expect(old.hasConsented, isTrue);

      // 판이 올라가면 예전 동의는 무효다
      SharedPreferences.setMockInitialValues({'disclaimer_version': 0});
      final stale = Repository();
      await stale.load();
      expect(stale.hasConsented, isFalse);
    });

    testWidgets('좁은 화면에서도 넘치지 않는다', (tester) async {
      usePhone(tester, size: const Size(320, 640));
      await tester.pumpWidget(wrap(repo, ConsentPage(onAccept: () {})));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('생활 과태료', () {
    testWidgets('갈래를 바꾸면 홈 내용이 바뀐다', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(wrap(repo, const HomePage()));
      await tester.pumpAndSettle();

      // 운전 갈래
      expect(find.text('물 튀김'), findsOneWidget);
      expect(find.textContaining('도로교통법 시행령'), findsOneWidget);

      await tester.tap(find.text('생활'));
      await tester.pumpAndSettle();

      expect(find.text('물 튀김'), findsNothing);
      expect(find.textContaining('폐기물관리법 시행령'), findsOneWidget);
      // 생활 갈래도 몰랐을 가능성 순이다
      expect(find.text('정해진 방법대로 내놓지 않기'), findsOneWidget);
      // 분류 칩도 갈래를 따라간다
      expect(find.text('무단투기'), findsWidgets);
      expect(find.text('주정차'), findsNothing);

      // 담배꽁초는 가장 잘 알려져 있어 아래쪽에 있다
      await scrollTo(tester, find.text('담배꽁초·휴지 버리기'));
      expect(find.text('담배꽁초·휴지 버리기'), findsOneWidget);
    });

    testWidgets('상세 — 횟수마다 금액이 다르면 횟수로 보여준다', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(wrap(repo, const DetailPage(conceptKey: 'order-ignore')));
      await tester.pumpAndSettle();

      expect(find.textContaining('1차'), findsWidgets);
      expect(find.textContaining('3차 이상'), findsWidgets);
      expect(find.textContaining('30만'), findsWidgets);
      expect(find.textContaining('100만'), findsWidgets);
      // 표 각주와 별표 비고에 둘 다 나온다
      expect(find.textContaining('최근 1년'), findsWidgets);
      // 차종 설명은 나오지 않는다
      expect(find.textContaining('승합 = '), findsNothing);
      // 출처는 이 별표가 속한 법령을 따라간다 (근거 패널은 아래쪽에 있다)
      await scrollTo(tester, find.textContaining('폐기물관리법 시행령'));
      expect(find.textContaining('폐기물관리법 시행령 별표 8'), findsOneWidget);
      expect(find.textContaining('도로교통법'), findsNothing);
      await scrollTo(tester, find.textContaining('2026. 3. 26.'));
      expect(find.textContaining('2026. 3. 26.'), findsWidgets);
    });

    testWidgets('상세 — 횟수와 무관하면 금액을 한 번만 보여준다', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
          wrap(repo, const DetailPage(conceptKey: 'litter-handheld')));
      await tester.pumpAndSettle();

      expect(find.textContaining('위반 횟수와 관계없이'), findsOneWidget);
      expect(find.textContaining('2차'), findsNothing);
      expect(find.textContaining('5만'), findsWidgets);
    });
  });
}
