"""RLS 동작 확인.

    python pipeline/check_rls.py

앱이 실제로 타는 경로(anon 키 + PostgREST)로 확인한다.
service_role 키는 RLS 를 우회하므로 이 검사를 대신할 수 없다.

SQL Editor 에서 set role anon 으로 흉내 내는 방법도 있지만, 편집기가
마지막 결과 하나만 보여줘서 여러 검사를 한 번에 보기 어렵다. 실제 키로
REST 를 때리는 쪽이 정확하고 결과도 한눈에 들어온다.

스키마나 정책을 고친 뒤에는 반드시 다시 돌린다.
"""
from __future__ import annotations

import sys

import requests

import config

# (테이블, anon 에게 보여야 하는 행 수)
# 도로교통법 4개 별표 + 폐기물관리법 별표 8
READABLE = [
    ("sources", 4 + 1),
    ("concepts", 125 + 62),
    ("violations", 183 + 89),
    ("violation_penalties", 556 + 267),
    ("data_version", 1),
    ("law_changes", 0),      # published=false 인 것은 보이지 않는다
]
BLOCKED = ["devices"]        # anon 이 아예 접근하지 못해야 하는 것

TIMEOUT = 30


def session(key: str) -> requests.Session:
    s = requests.Session()
    s.headers.update({"apikey": key, "Authorization": f"Bearer {key}",
                      "Content-Type": "application/json"})
    return s


def count(s: requests.Session, url: str, table: str, **params):
    """(행 수 또는 None, HTTP 코드, 오류 코드)."""
    r = s.get(f"{url}/rest/v1/{table}",
              params={"select": "*", "limit": 1, **params},
              headers={"Prefer": "count=exact"}, timeout=TIMEOUT)
    if r.status_code >= 400:
        try:
            code = r.json().get("code", "")
        except ValueError:
            code = ""
        return None, r.status_code, code
    return int(r.headers["content-range"].split("/")[-1]), r.status_code, ""


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    url = config.require("SUPABASE_URL").rstrip("/")
    anon = config.require("SUPABASE_ANON_KEY",
                          "Project Settings > API 의 publishable 키. 공개 키라 앱에 들어간다.")
    svc = config.require("SUPABASE_SERVICE_KEY")
    if "secret" in anon:
        raise SystemExit("SUPABASE_ANON_KEY 에 secret 키가 들어갔습니다. publishable 키를 넣으세요.")

    A, S = session(anon), session(svc)
    results: list[bool] = []

    def record(ok: bool, line: str) -> None:
        results.append(ok)
        print(f"   {line}  {'OK' if ok else '<- 문제'}")

    print("[1] anon 이 읽을 수 있어야 하는 것")
    for table, expected in READABLE:
        n, code, err = count(A, url, table)
        record(n == expected,
               f"{table:22} {str(n):>5} (기대 {expected:>3})  HTTP {code} {err}")

    print("\n[2] anon 이 접근하지 못해야 하는 것")
    for table in BLOCKED:
        n, code, err = count(A, url, table)
        record(n is None, f"{table:22} HTTP {code} {err}")

    print("\n[3] anon 이 쓰지 못해야 한다")
    probe = {"id": "__rls_write__", "source_slug": "byeolpyo6", "ref": "테스트",
             "item_no": "0", "action": "쓰기 시도", "legal_basis": "제0조"}
    r = A.post(f"{url}/rest/v1/violations", json=probe, timeout=TIMEOUT)
    blocked = r.status_code >= 400
    record(blocked, f"insert violations      HTTP {r.status_code}")
    if not blocked:   # 뚫렸으면 흔적을 지운다
        S.delete(f"{url}/rest/v1/violations",
                 params={"id": "eq.__rls_write__"}, timeout=TIMEOUT)

    print("\n[4] 검수중(needs_review) 행이 anon 에게 숨겨지는가")
    hidden = {**probe, "id": "__rls_hidden__", "action": "검수 중", "needs_review": True}
    S.post(f"{url}/rest/v1/violations", headers={"Prefer": "return=minimal"},
           json=hidden, timeout=TIMEOUT)
    try:
        seen, _, _ = count(A, url, "violations", id="eq.__rls_hidden__")
        by_svc, _, _ = count(S, url, "violations", id="eq.__rls_hidden__")
        record(seen == 0 and by_svc == 1,
               f"service_role 에게 {by_svc}건 / anon 에게 {seen}건")
    finally:
        S.delete(f"{url}/rest/v1/violations",
                 params={"id": "eq.__rls_hidden__"}, timeout=TIMEOUT)
    left, _, _ = count(S, url, "violations")
    record(left == dict(READABLE)["violations"], f"정리 후 violations {left}건")

    print("\n전부 통과" if all(results) else "\n문제 있는 항목이 있습니다")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
