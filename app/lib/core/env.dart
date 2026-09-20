import 'package:firebase_core/firebase_core.dart';

/// 빌드 시점에 주입되는 값.
///
///   flutter run --dart-define-from-file=env.json
///
/// env.json 은 gitignore 된다. pipeline/export_seed.py 가 루트 .env 를 읽어
/// 만들어 준다.
///
/// Supabase anon 키와 Firebase 설정값은 둘 다 앱에 그대로 들어가는 공개
/// 값이라 비밀이 아니다. 그래도 저장소에 두지 않는 이유는 교체가 번거로워지고,
/// 개발용과 운영용을 바꿔 끼우기 어려워지기 때문이다.
///
/// 값이 없으면 앱은 번들된 seed 만으로 동작한다. 갱신과 푸시만 못 한다.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasBackend =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  // --- Firebase (FCM) ------------------------------------------------------
  // google-services.json 을 쓰지 않는다. 그 파일을 넣으면 Gradle 플러그인까지
  // 딸려 오고, 파일이 없는 빌드가 통째로 깨진다. 값만 넘기면 같은 일을 한다.
  // Firebase 콘솔 > 프로젝트 설정 > 내 앱 에서 가져온다.

  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId =
      String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get hasFirebase =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  static FirebaseOptions get firebaseOptions => FirebaseOptions(
        apiKey: firebaseApiKey,
        appId: firebaseAppId,
        messagingSenderId: firebaseSenderId,
        projectId: firebaseProjectId,
      );
}
