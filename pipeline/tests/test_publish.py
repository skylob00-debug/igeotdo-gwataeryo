"""적재 검증.

이 환경에는 Postgres 가 없어 SQL 을 실행해 볼 수 없다. 대신 스키마 파일과
publish.py 가 어긋나지 않는지를 확인한다. 실행 검증만큼은 아니지만,
"컬럼을 코드에만 추가하고 마이그레이션에 빠뜨리는" 종류의 사고는 잡는다.

  1. 보낼 행의 컬럼이 모두 스키마에 있는가
  2. 보낼 값이 모두 CHECK 제약이 허용하는 값인가
  3. 검수가 안 끝났거나 금액이 없으면 적재를 막는가
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

import normalize
import publish

MIGRATIONS = sorted((Path(__file__).resolve().parents[2] / "supabase" / "migrations")
                    .glob("*.sql"))
SQL = "\n".join(p.read_text(encoding="utf-8") for p in MIGRATIONS)

# 컬럼 정의가 아닌 줄 (제약, 인덱스 등)
_NOT_A_COLUMN = {"primary", "constraint", "check", "foreign", "unique", "exclude"}


def table_columns(table: str) -> set[str]:
    """마이그레이션 전체를 순서대로 읽어 그 테이블의 최종 컬럼을 구한다.

    create table 이후의 alter table add/drop column 까지 반영한다.
    0001 만 보면 나중 마이그레이션에서 옮기거나 지운 컬럼을 놓친다.
    """
    cols: set[str] = set()
    found = False
    for path in MIGRATIONS:
        sql = path.read_text(encoding="utf-8")
        m = re.search(rf"create table if not exists public\.{table} \((.*?)\n\);",
                      sql, flags=re.S)
        if m:
            found = True
            for line in m.group(1).splitlines():
                word = re.match(r"(\w+)\s", line.strip())
                if word and word.group(1).lower() not in _NOT_A_COLUMN:
                    cols.add(word.group(1))
        for blk in re.findall(rf"alter table public\.{table}\s(.*?);", sql, flags=re.S):
            for add in re.findall(r"add column if not exists\s+(\w+)", blk):
                cols.add(add)
            for drop in re.findall(r"drop column if exists\s+(\w+)", blk):
                cols.discard(drop)
    assert found, f"{table} 테이블 정의를 찾지 못했습니다"
    return cols


def check_values(column: str) -> set[str]:
    """check (col in ('a','b')) 에서 허용 값을 뽑는다.

    마지막에 나오는 정의가 이긴다. 뒤 마이그레이션이 제약을 drop 하고
    다시 add 하는 경우가 있다 (0007 의 vehicle_type, audience).
    """
    hits = re.findall(rf"check \({column} in \(([^)]*)\)\)", SQL)
    assert hits, f"{column} 의 check 제약을 찾지 못했습니다"
    return set(re.findall(r"'([^']*)'", hits[-1]))


@pytest.fixture(scope="module")
def payload() -> publish.Payload:
    return publish.collect()[1]


def _record(**over) -> normalize.Record:
    base = dict(
        id="test-1", source="byeolpyo8", byeolpyo="별표 8", kind="ticket",
        category="driving",
        item_no="1", sub_no=None, ref="제1호", action="속도위반", parent_action="",
        basis="제17조제3항",
        penalties=[normalize.Penalty(vehicle="car", amount_krw=120_000)],
    )
    base.update(over)
    return normalize.Record(**base)


MANIFEST = {
    "law_name": "도로교통법 시행령", "mst": "283551",
    "promulgation_date": "20260219", "enforce_date": "20260801",
    "byeolpyo": {"byeolpyo8": {"sha256": "abc", "hwp_sha256": "def"}},
}
META = {"byeolpyo8": {"label": "별표 8", "title": "범칙행위 및 범칙금액",
                      "amended": "2025. 6. 2.", "notes": ["비고 1"]}}
# 적재 차단 검사용 최소 큐레이션. 실제 curation.json 과 무관하게 돌린다.
STUB = {"concepts": {"test": {"title": "테스트", "summary": "설명",
                              "subcategory": "기타", "awareness": 0}},
        "rows": {"test-1": "test"}}


# --- 스키마와의 정합 -------------------------------------------------------

def test_보낼_컬럼이_모두_스키마에_있다(payload):
    for table, rows in (("sources", payload.sources),
                        ("concepts", payload.concepts),
                        ("violations", payload.violations),
                        ("violation_penalties", payload.penalties)):
        allowed = table_columns(table)
        used = {k for row in rows for k in row}
        missing = used - allowed
        assert not missing, f"{table} 스키마에 없는 컬럼: {sorted(missing)}"


def test_보낼_값이_모두_check_제약을_통과한다(payload):
    for col, rows, key in (("category", payload.violations, "category"),
                           ("zone", payload.violations, "zone"),
                           ("kind", payload.penalties, "kind"),
                           ("vehicle_type", payload.penalties, "vehicle_type")):
        allowed = check_values(col)
        used = {row[key] for row in rows}
        assert used <= allowed, f"{col}: 허용되지 않는 값 {sorted(used - allowed)}"


def test_금액_제약을_미리_만족한다(payload):
    for p in payload.penalties:
        assert p["amount_krw"] > 0
        if p["surcharge_krw"] is not None:
            assert p["surcharge_krw"] >= p["amount_krw"]


def test_기본키가_중복되지_않는다(payload):
    keys = [(p["violation_id"], p["kind"], p["vehicle_type"],
             p["offense_count"], p["effective_from"])
            for p in payload.penalties]
    assert len(keys) == len(set(keys))
    ids = [v["id"] for v in payload.violations]
    assert len(ids) == len(set(ids))


def test_외래키가_맞물린다(payload):
    slugs = {s["slug"] for s in payload.sources}
    assert {v["source_slug"] for v in payload.violations} <= slugs
    assert {p["violation_id"] for p in payload.penalties} <= set(payload.violation_ids)


# --- 실제 데이터 -----------------------------------------------------------

def test_현재_데이터가_그대로_실린다(payload):
    # 도로교통법 4개 별표 + 폐기물관리법 별표 8
    assert len(payload.sources) == 5
    assert len(payload.concepts) == 125 + 62
    assert len(payload.violations) == 183 + 89
    assert len(payload.penalties) == 556 + 267
    assert all(v["needs_review"] is False for v in payload.violations)


def test_갈래가_갈린다(payload):
    from collections import Counter
    cats = Counter(c["category"] for c in payload.concepts)
    assert cats == {"driving": 125, "waste": 62}
    aud = Counter(c["audience"] for c in payload.concepts)
    assert aud["resident"] == 7, "생활인 대상은 7가지다 (tests/test_living.py 참고)"
    # 생활 과태료에는 차종도 보호구역도 없다
    living = {v["id"] for v in payload.violations if v["category"] == "waste"}
    assert all(v["zone"] == "none" for v in payload.violations
               if v["id"] in living)
    assert {p["vehicle_type"] for p in payload.penalties
            if p["violation_id"] in living} == {"none"}
    # 거꾸로 도로교통법에는 횟수 구분이 없다
    assert {p["offense_count"] for p in payload.penalties
            if p["violation_id"] not in living} == {1}


def test_모든_행이_개념에_붙는다(payload):
    keys = {c["key"] for c in payload.concepts}
    used = {v["concept"] for v in payload.violations}
    assert None not in used
    assert used <= keys
    assert used == keys, f"쓰이지 않는 개념: {sorted(keys - used)}"


def test_한_칸에_금액이_하나뿐이다(payload):
    """개념·종류·구역·차종이 같으면 금액도 하나여야 카드에 표로 그릴 수 있다."""
    where = {v["id"]: (v["concept"], v["zone"]) for v in payload.violations}
    cell: dict[tuple, set] = {}
    for p in payload.penalties:
        concept, zone = where[p["violation_id"]]
        cell.setdefault(
            (concept, p["kind"], zone, p["vehicle_type"], p["offense_count"]),
            set()).add((p["amount_krw"], p["surcharge_krw"]))
    bad = {k: v for k, v in cell.items() if len(v) > 1}
    assert not bad, f"금액이 갈리는 칸: {sorted(bad, key=str)[:3]}"


def test_보호구역_구분이_붙는다(payload):
    zones = {v["id"]: v["zone"] for v in payload.violations}
    assert zones["byeolpyo6-1"] == "none"
    assert zones["byeolpyo8-4"] == "none"
    assert zones["byeolpyo7-1"] == "both"        # 구역 구분 없이 같은 금액
    assert zones["byeolpyo7-3-가"] == "school"
    assert zones["byeolpyo7-3-나"] == "senior"
    assert zones["byeolpyo10-6-가"] == "school"
    assert zones["byeolpyo10-6-나"] == "senior"


def test_대표_카드가_네_칸을_다_채운다(payload):
    """신호위반 카드는 일반/보호구역 x 과태료/범칙금 네 칸이 다 있어야 한다."""
    ids = {v["id"]: v for v in payload.violations if v["concept"] == "signal"}
    assert len(ids) == 4
    got = {}
    for p in payload.penalties:
        if p["violation_id"] in ids and p["vehicle_type"] == "car":
            got[(ids[p["violation_id"]]["zone"], p["kind"])] = p["amount_krw"]
    assert got == {("none", "fine"): 70_000, ("none", "ticket"): 60_000,
                   ("both", "fine"): 130_000, ("both", "ticket"): 120_000}


def test_개념_문구가_비어있지_않다(payload):
    for c in payload.concepts:
        assert c["title"] and len(c["title"]) <= 40, c
        assert c["summary"], c["key"]
        assert c["subcategory"], c["key"]
        assert 0 <= c["awareness_score"] <= 100, c


def test_시행일이_별표가_속한_법령을_따른다(payload):
    """법령이 둘이므로 시행일도 둘이다. 하나로 뭉뚱그리면 안 된다."""
    by_slug = {s["slug"]: s["enforce_date"] for s in payload.sources}
    assert by_slug["byeolpyo6"] == "2026-08-01"      # 도로교통법 시행령
    assert by_slug["waste8"] == "2026-03-26"         # 폐기물관리법 시행령
    source_of = {v["id"]: v["source_slug"] for v in payload.violations}
    for p in payload.penalties:
        assert p["effective_from"] == by_slug[source_of[p["violation_id"]]]
        assert p["effective_to"] is None


def test_비고와_해시가_출처에_실린다(payload):
    by_slug = {s["slug"]: s for s in payload.sources}
    assert len(by_slug["byeolpyo6"]["notes"]) == 4      # 차종 정의 3 + 가중 조건 1
    assert len(by_slug["byeolpyo8"]["notes"]) == 5
    assert len(by_slug["waste8"]["notes"]) == 1        # 일반기준(가중·감경)
    assert set(by_slug) == {"byeolpyo6", "byeolpyo7", "byeolpyo8",
                            "byeolpyo10", "waste8"}
    assert all(len(s["content_sha256"]) == 64 for s in by_slug.values())


def test_2시간_가중금액이_살아있다(payload):
    주정차 = [p for p in payload.penalties
             if p["violation_id"] == "byeolpyo6-6" and p["vehicle_type"] == "car"]
    assert len(주정차) == 1
    assert (주정차[0]["amount_krw"], 주정차[0]["surcharge_krw"]) == (40_000, 50_000)


def test_누진_가산규칙이_살아있다(payload):
    누진 = [v for v in payload.violations if v["penalty_formula"]]
    assert len(누진) == 1
    assert 누진[0]["id"] == "byeolpyo6-10-3-나"


# --- 적재 차단 -------------------------------------------------------------

def test_검수가_안_끝났으면_적재를_막는다():
    rec = _record(needs_review=True, review_note="금액 묶음이 둘 이상입니다")
    with pytest.raises(SystemExit, match="검수가 끝나지 않았습니다"):
        publish.build_payload(MANIFEST, META, [rec], STUB)


def test_금액이_없으면_적재를_막는다():
    with pytest.raises(SystemExit, match="금액이 없습니다"):
        publish.build_payload(MANIFEST, META, [_record(penalties=[])], STUB)


def test_가중금액이_기본금액보다_작으면_막는다():
    bad = normalize.Penalty(vehicle="car", amount_krw=50_000, surcharge_krw=40_000)
    with pytest.raises(SystemExit, match="가중 금액"):
        publish.build_payload(MANIFEST, META, [_record(penalties=[bad])], STUB)


def test_차종이_중복되면_막는다():
    dup = [normalize.Penalty(vehicle="car", amount_krw=50_000),
           normalize.Penalty(vehicle="car", amount_krw=60_000)]
    with pytest.raises(SystemExit, match="중복"):
        publish.build_payload(MANIFEST, META, [_record(penalties=dup)], STUB)


def test_시행일이_없으면_막는다():
    broken = {**MANIFEST, "enforce_date": ""}
    with pytest.raises(SystemExit, match="enforce_date"):
        publish.build_payload(broken, META, [_record()], STUB)


def test_개념_매핑이_없으면_막는다():
    with pytest.raises(SystemExit, match="개념 매핑이 없습니다"):
        publish.build_payload(MANIFEST, META, [_record(id="없는id")], STUB)


def test_폐지는_지우지_않고_표시만_한다():
    """별표에서 사라진 행은 DELETE 하지 않는다.

    지우면 사용자가 저장(즐겨찾기)한 항목이 말없이 없어진다.
    """
    rows = [
        {"id": "a", "source_slug": "byeolpyo6", "repealed_at": None},        # 계속 실림
        {"id": "b", "source_slug": "byeolpyo6", "repealed_at": None},        # 이번에 사라짐
        {"id": "c", "source_slug": "byeolpyo8", "repealed_at": None},        # 이번에 사라짐
        {"id": "d", "source_slug": "byeolpyo6", "repealed_at": "2025-03-18"},  # 이미 폐지
        {"id": "e", "source_slug": "byeolpyo8", "repealed_at": "2025-06-02"},  # 되살아남
    ]
    by_source, revive = publish.plan_repeals(rows, {"a", "e"})
    assert by_source == {"byeolpyo6": ["b"], "byeolpyo8": ["c"]}
    assert revive == ["e"]


def test_이미_폐지된_행은_다시_건드리지_않는다():
    rows = [{"id": "d", "source_slug": "byeolpyo6", "repealed_at": "2025-03-18"}]
    by_source, revive = publish.plan_repeals(rows, set())
    assert by_source == {} and revive == []


def test_별표_개정일_파싱():
    assert publish.korean_date("2025. 3. 18.") == "2025-03-18"
    assert publish.korean_date("2025. 6. 2.") == "2025-06-02"
    assert publish.korean_date("2020. 12. 1.") == "2020-12-01"
    assert publish.korean_date(None) is None
    assert publish.korean_date("개정 없음") is None


def test_폐지_컬럼이_스키마에_있다():
    cols = table_columns("violations")
    assert {"repealed_at", "repealed_reason"} <= cols


def test_날짜_변환():
    assert publish._date("20260801") == "2026-08-01"
    assert publish._date("") is None
    assert publish._date("2026") is None
