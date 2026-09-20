"""google-services.json 에서 .env 에 넣을 네 줄을 뽑는다.

    .venv/Scripts/python.exe pipeline/firebase_env.py ~/Downloads/google-services.json

google-services.json 을 앱에 넣지 않는 이유는 app/lib/core/env.dart 주석에 있다.
요약하면 그 파일을 넣는 순간 google-services Gradle 플러그인이 딸려 오고,
파일이 없는 빌드(CI, 다른 사람 체크아웃)가 통째로 깨진다. 값만 있으면 된다.

콘솔 화면에서 눈으로 옮겨 적어도 되지만, Android 앱의 API 키는 프로젝트
설정 화면의 '웹 API 키'와 다를 수 있다. 파일에서 뽑는 쪽이 확실하다.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def extract(data: dict, package: str | None = None) -> dict[str, str]:
    info = data["project_info"]
    clients = data["client"]
    if package:
        clients = [c for c in clients
                   if c["client_info"]["android_client_info"]["package_name"] == package]
        if not clients:
            raise SystemExit(f"{package} 로 등록된 앱이 파일에 없습니다")
    if len(clients) > 1:
        names = [c["client_info"]["android_client_info"]["package_name"] for c in clients]
        raise SystemExit(f"앱이 여러 개입니다. 패키지 이름을 함께 주세요: {', '.join(names)}")
    client = clients[0]
    return {
        "FIREBASE_API_KEY": client["api_key"][0]["current_key"],
        "FIREBASE_APP_ID": client["client_info"]["mobilesdk_app_id"],
        "FIREBASE_SENDER_ID": info["project_number"],
        "FIREBASE_PROJECT_ID": info["project_id"],
    }


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = Path(sys.argv[1]).expanduser()
    package = sys.argv[2] if len(sys.argv) > 2 else None
    values = extract(json.loads(path.read_text(encoding="utf-8")), package)

    print("# .env 에 아래 네 줄을 넣고 export_seed.py 를 다시 돌리세요.")
    for k, v in values.items():
        print(f"{k}={v}")


if __name__ == "__main__":
    main()
