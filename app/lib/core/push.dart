import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'env.dart';

/// FCM 푸시.
///
/// Firebase 설정값은 빌드 인자로 넘긴다. google-services.json 을 쓰지 않는
/// 이유는, 그 파일이 있으면 Gradle 플러그인까지 딸려 오고 파일이 없는 빌드가
/// 통째로 깨지기 때문이다. 설정이 없으면 푸시만 건너뛰고 앱은 그대로 돈다.
///
/// 보내는 쪽은 supabase/functions/push-notify 다.
/// 사람이 검수해 published=true 로 바꾼 법령 변경만 나간다.
class Push {
  Push({required this.onRegister});

  /// 토큰을 서버에 등록하는 함수. Repository 가 넘겨 준다.
  final Future<void> Function(String token, String platform, List<String> topics)
      onRegister;

  static const _topicAll = 'law-changes';

  FirebaseMessaging? _messaging;
  String? token;

  bool get isConfigured => Env.hasFirebase;
  bool get isReady => _messaging != null;

  /// 앱이 뜬 뒤에 부른다. 실패해도 앱은 그대로 돈다.
  Future<void> start() async {
    if (!isConfigured) {
      debugPrint('[push] Firebase 설정이 없어 푸시를 건너뜁니다');
      return;
    }
    try {
      await Firebase.initializeApp(options: Env.firebaseOptions);
      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;

      // Android 13+ 와 iOS 는 사용자가 허용해야 한다. 거절해도 앱은 돈다.
      final settings = await messaging.requestPermission();
      final allowed =
          settings.authorizationStatus != AuthorizationStatus.denied;
      if (!allowed) {
        debugPrint('[push] 알림 권한이 거절됐습니다');
        return;
      }

      token = await messaging.getToken();
      if (token != null) await _register(token!);

      // 토큰은 재설치·복원 때 바뀐다. 바뀌면 다시 등록한다.
      messaging.onTokenRefresh.listen((t) {
        token = t;
        _register(t);
      });

      await messaging.subscribeToTopic(_topicAll);
    } catch (e) {
      debugPrint('[push] 시작하지 못했습니다: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await onRegister(token, defaultTargetPlatform.name, const [_topicAll]);
    } catch (e) {
      debugPrint('[push] 토큰 등록 실패: $e');
    }
  }

  /// 앱이 켜져 있을 때 온 알림. 화면에서 배지를 띄우는 데 쓴다.
  Stream<RemoteMessage> get onMessage =>
      isReady ? FirebaseMessaging.onMessage : const Stream.empty();

  /// 알림을 눌러 앱이 열렸을 때.
  Stream<RemoteMessage> get onOpened =>
      isReady ? FirebaseMessaging.onMessageOpenedApp : const Stream.empty();

  /// 앱이 꺼진 상태에서 알림을 눌러 열린 경우.
  Future<RemoteMessage?> initialMessage() async =>
      isReady ? FirebaseMessaging.instance.getInitialMessage() : null;
}
