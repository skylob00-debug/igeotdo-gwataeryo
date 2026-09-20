package kr.co.igeotdo.gwataeryo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /**
     * 법령 변경 알림 채널을 만든다.
     *
     * AndroidManifest 의 default_notification_channel_id 는 "이 채널을 써라"고
     * 지정할 뿐, 채널을 만들어 주지는 않는다. firebase_messaging 플러그인도
     * 채널을 만들지 않는다. 아무도 만들지 않으면 FCM 이
     * fcm_fallback_notification_channel 로 떨어뜨리고, 사용자는 알림 설정에서
     * '기타' 라는 이름을 보게 된다. 끄고 켜는 기준도 우리 것이 아니게 된다.
     *
     * 채널을 앱 시작 때 만들어 두면 push-notify 가 보내는 channel_id 와
     * manifest 의 기본값이 모두 이 채널을 가리킨다.
     * 이미 있으면 아무 일도 하지 않는다(설명·중요도는 사용자가 바꿀 수 있고,
     * 그 선택을 앱이 덮어쓰지 않는다).
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "법령 변경 알림",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "과태료·범칙금 금액이 바뀌거나 새 규정이 생기면 알려드립니다."
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
    }

    companion object {
        /** supabase/functions/push-notify 가 보내는 channel_id 와 같아야 한다. */
        private const val CHANNEL_ID = "law_changes"
    }
}
