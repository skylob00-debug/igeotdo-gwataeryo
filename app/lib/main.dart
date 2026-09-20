import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push.dart';
import 'core/theme.dart';
import 'data/providers.dart';
import 'data/repository.dart';
import 'features/alerts_page.dart';
import 'features/consent_page.dart';
import 'features/home_page.dart';
import 'features/saved_page.dart';
import 'features/search_page.dart';

/// 앱이 꺼져 있을 때 오는 알림. 최상위 함수여야 한다.
///
/// 지금은 아무것도 하지 않는다. 시스템이 알림을 띄우고, 사용자가 누르면
/// getInitialMessage() 로 이어진다. 여기서 화면을 건드릴 수는 없다.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 번들된 seed 를 먼저 띄운다. 네트워크를 기다리지 않는다.
  final repo = Repository();
  await repo.load();

  runApp(ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(repo)],
    child: const App(),
  ));
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '이것도 과태료?',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      );
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  static const _alertsTab = 3;
  static const _pages = [HomePage(), SearchPage(), SavedPage(), AlertsPage()];

  int _tab = 0;
  bool _hasNewAlert = false;
  bool _consented = false;

  @override
  void initState() {
    super.initState();
    _consented = ref.read(repositoryProvider).hasConsented;
    if (_consented) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
    }
  }

  /// 갱신 확인과 푸시 등록. 동의 전에는 부르지 않는다.
  ///
  /// 면책 고지를 읽기도 전에 알림 권한을 묻는 것은 무례하고, 거절률도 높다.
  void _begin() {
    // 화면을 띄운 뒤 조용히 갱신을 확인한다. 실패해도 앱은 그대로 돈다.
    ref.read(dataProvider.notifier).refresh();
    _startPush();
  }

  Future<void> _accept() async {
    await ref.read(repositoryProvider).acceptConsent();
    if (!mounted) return;
    setState(() => _consented = true);
    _begin();
  }

  Future<void> _startPush() async {
    final repo = ref.read(repositoryProvider);
    final push = Push(onRegister: repo.registerDevice);

    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    await push.start();
    if (!mounted) return;

    // 앱이 켜져 있을 때 온 알림은 배지만 띄운다. 화면을 가로채지 않는다.
    push.onMessage.listen((_) {
      if (mounted) setState(() => _hasNewAlert = true);
      ref.invalidate(changesProvider);
    });

    // 알림을 눌러 들어온 경우 알림 탭으로.
    push.onOpened.listen((_) => _openAlerts());
    if (await push.initialMessage() != null) _openAlerts();
  }

  void _openAlerts() {
    if (!mounted) return;
    ref.invalidate(changesProvider);
    setState(() {
      _tab = _alertsTab;
      _hasNewAlert = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_consented) return ConsentPage(onAccept: _accept);
    return Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(index: _tab, children: _pages),
        ),
        bottomNavigationBar: _BottomBar(
          index: _tab,
          badgeOn: _hasNewAlert ? _alertsTab : null,
          onTap: (i) => setState(() {
            _tab = i;
            if (i == _alertsTab) _hasNewAlert = false;
          }),
        ),
      );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.index,
    required this.onTap,
    this.badgeOn,
  });

  final int index;
  final ValueChanged<int> onTap;

  /// 읽지 않은 알림이 있는 탭.
  final int? badgeOn;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, '홈'),
    (Icons.search_rounded, Icons.search_rounded, '검색'),
    (Icons.bookmark_border_rounded, Icons.bookmark_rounded, '저장'),
    (Icons.notifications_none_rounded, Icons.notifications_rounded, '알림'),
  ];

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => onTap(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                i == index ? _items[i].$2 : _items[i].$1,
                                size: 21,
                                color: i == index
                                    ? AppColors.accent
                                    : AppColors.muted,
                              ),
                              if (badgeOn == i)
                                Positioned(
                                  right: -2,
                                  top: -1,
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: AppColors.accentIcon,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _items[i].$3,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: i == index
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: i == index
                                  ? AppColors.accent
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
