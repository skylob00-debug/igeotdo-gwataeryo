"""법제처 국가법령정보 OPEN API (law.go.kr/DRF) 클라이언트."""
from __future__ import annotations

import time
from urllib.parse import urlencode

import requests

import config

BASE = "https://www.law.go.kr/DRF"
HEADERS = {"User-Agent": "gwataeryo-alrimi/0.1", "Referer": "https://www.law.go.kr/"}

# 운영에서는 open.law.go.kr 에서 발급받은 OC(신청 이메일 ID 앞부분)를 .env 에 넣는다.
# 'test' 는 법제처가 제공하는 테스트용 값이라 운영에 쓰면 안 된다.
def oc() -> str:
    return config.get("LAW_API_OC", "test")


class LawApiError(RuntimeError):
    pass


def _get(path: str, params: dict, *, retries: int = 3) -> str:
    params = {"OC": oc(), **params}
    url = f"{BASE}/{path}?{urlencode(params)}"
    last: Exception | None = None
    for attempt in range(retries):
        try:
            r = requests.get(url, headers=HEADERS, timeout=60)
            r.raise_for_status()
            r.encoding = "utf-8"
            if "<resultCode>" in r.text and "<resultCode>00</resultCode>" not in r.text:
                raise LawApiError(f"API 오류 응답: {r.text[:300]}")
            return r.text
        except Exception as exc:  # noqa: BLE001
            last = exc
            time.sleep(1.5 * (attempt + 1))
    raise LawApiError(f"{url} 호출 실패") from last


def search_law(query: str, *, display: int = 20) -> str:
    """법령 목록 조회 (target=law). 법령일련번호(MST)/시행일자 확인용."""
    return _get("lawSearch.do", {"target": "law", "query": query,
                                 "type": "XML", "display": display})


def search_effective_law(query: str, *, display: int = 100) -> str:
    """시행일 법령 목록 조회 (target=eflaw). 미래 시행 예정 법령이 포함된다."""
    return _get("lawSearch.do", {"target": "eflaw", "query": query,
                                 "type": "XML", "display": display, "sort": "efdes"})


def law_body(mst: str) -> str:
    """법령 본문 조회 (target=law). 별표내용(박스아트 표)까지 포함된다."""
    return _get("lawService.do", {"target": "law", "MST": mst, "type": "XML"})
