"""환경 설정. 프로젝트 루트의 .env 를 읽어 os.environ 에 채운다.

python-dotenv 를 쓰지 않는 이유는 의존성을 하나 줄이기 위해서다.
필요한 건 KEY=VALUE 한 줄 형식뿐이다.
이미 셸이나 CI 에 설정된 값은 덮어쓰지 않는다.
"""
from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / ".env"

_loaded = False


def load(path: Path | None = None) -> None:
    global _loaded
    if _loaded and path is None:
        return
    target = path or ENV_FILE
    if target.exists():
        for line in target.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value
    if path is None:
        _loaded = True


def get(name: str, default: str = "") -> str:
    load()
    return os.environ.get(name, default)


def require(name: str, hint: str = "") -> str:
    value = get(name)
    if not value:
        raise SystemExit(
            f"환경변수 {name} 이(가) 없습니다. .env 에 넣거나 셸에서 지정하세요."
            + (f"\n  {hint}" if hint else ""))
    return value
