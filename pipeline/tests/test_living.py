"""생활 과태료 별표 검증 (적재 전 단계).

아직 normalize/publish 를 타지 않는다. 스키마(위반 횟수 축, 차종 없음)를
정하기 전이라 추출 결과만 본다. 적재 대상이 되면 test_pipeline.py 쪽으로
옮기고 여기서는 뺀다.

도로교통법 별표와 표의 생김새가 달라서 추출 전략을 갈랐다(extract_tables.Scheme).
여기서 지키려는 것은 두 가지다.

  1. 새 전략이 조용히 항목을 흘리지 않는지 (건수 스냅샷)
  2. 계층·금액 매핑이 실제 원문과 맞는지 (실측 대조)

2번이 특히 중요하다. 이 표에는 같은 문구가 금액만 다르게 네 번 나오는
항목이 있어서(그 밖의 준수사항을 이행하지 않은 경우), 행을 잘못 붙이면
그럴듯하게 틀린 값이 나온다.
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

import pytest

import extract_tables

RAW = Path(__file__).resolve().parents[1] / "raw"

# 원문 sha256 - 개정되면 달라진다 (pipeline/raw/manifest.json 과 맞춰 둔다)
EXPECTED_SOURCE = "9398921435ee42f1217bce5d4daa4cc28f9faa74d7069b54dc06eb91dbb94e03"

EXPECTED_LEAVES = 89        # 행위 (금액이 붙은 잎)
EXPECTED_UNITS = 267        # 행위 x 위반 횟수
EXPECTED_CONCEPTS = 62      # 큐레이션 개념
EXPECTED_RESIDENT = 7       # 그중 일반 시민 대상 (홈 피드에 나갈 것)

CURATION = Path(__file__).resolve().parents[1] / "curation_living.json"


@pytest.fixture(scope="module")
def waste() -> extract_tables.Byeolpyo:
    return extract_tables.parse("waste8", RAW)


def _unit(waste, ref: str, offense: str) -> extract_tables.Unit:
    hits = [u for u in waste.units if u.ref == ref and u.offense == offense]
    assert len(hits) == 1, f"{ref} {offense}: {len(hits)}건 (1건이어야 함)"
    return hits[0]


def _amounts(waste, ref: str) -> list[str]:
    """1차 / 2차 / 3차 이상 금액을 순서대로."""
    return [_unit(waste, ref, o).amount for o in ("1차", "2차", "3차 이상")]


def test_원문이_바뀌지_않았다():
    manifest = json.loads((RAW / "manifest.json").read_text(encoding="utf-8"))
    actual = manifest["laws"]["폐기물관리법 시행령"]["byeolpyo"]["waste8"]["sha256"]
    assert actual == EXPECTED_SOURCE, (
        f"waste8 원문이 바뀌었습니다. 개정 여부를 확인하고 "
        f"검수 후 기대값을 갱신하세요. ({actual})")


def test_추출_건수(waste):
    assert len(waste.units) == EXPECTED_UNITS
    assert len({u.ref for u in waste.units}) == EXPECTED_LEAVES
    assert waste.review_units == []


def test_별표_머리말(waste):
    assert waste.label == "별표 8"
    assert waste.title.startswith("과태료의 부과기준")
    assert waste.amended == "2024. 8. 13."
    # 일반기준(가중·감경 규칙)은 비고로 실어야 앱에서 보여줄 수 있다
    assert waste.notes and "위반행위의 횟수" in waste.notes[0]


def test_모든_단위에_금액과_근거가_있다(waste):
    for u in waste.units:
        assert u.amount.endswith("만원"), u.ref
        assert u.basis, f"{u.ref}: 근거 법조문이 비었습니다"
        assert u.offense in ("1차", "2차", "3차 이상"), u.ref


def test_실측_무단투기(waste):
    # 가장 많이 찾는 값들. 셋 다 횟수에 상관없이 같은 금액이다.
    assert _amounts(waste, "가목 1) 가)") == ["5만원"] * 3       # 담배꽁초·휴지
    assert _amounts(waste, "가목 1) 나)") == ["20만원"] * 3      # 비닐봉지 등
    assert _amounts(waste, "가목 1) 다)") == ["20만원"] * 3      # 휴식·행락 쓰레기
    assert _amounts(waste, "가목 1) 라)") == ["50만원"] * 3      # 차량·손수레
    assert _amounts(waste, "가목 1) 마)") == ["100만원"] * 3     # 사업활동 과정


def test_실측_횟수마다_금액이_올라가는_것(waste):
    # 조치명령 미이행
    assert _amounts(waste, "나목") == ["30만원", "70만원", "100만원"]
    # 유해성기준 위반 재활용 (쉼표가 든 금액)
    assert _amounts(waste, "마목") == ["500만원", "700만원", "1,000만원"]
    # 주거생활 폐기물을 조례가 정한 방법대로 내놓지 않은 경우
    # (법 제15조에 '종량제 봉투' 라는 말은 없다. 배출 방법은 조례 소관이다)
    assert _amounts(waste, "사목 1)") == ["10만원", "20만원", "30만원"]


def test_같은_문구가_여러_번_나와도_행을_안_섞는다(waste):
    """'그 밖의 준수사항을 이행하지 않은 경우' 는 금액만 다르게 네 번 나온다.

    문구로 찾으면 첫 번째에 붙는다. 행 위치로 붙여야 맞는다.
    """
    same = [u for u in waste.units
            if u.action.startswith("그 밖의 준수사항을 이행하지 않은")]
    refs = sorted({u.ref for u in same})
    assert len(refs) >= 3, refs
    # 로목 4) 는 300/500/700 이다 (앞쪽의 200/400/600 과 다르다)
    assert _amounts(waste, "로목 4)") == ["300만원", "500만원", "700만원"]


def test_계층이_참조에_그대로_남는다(waste):
    u = _unit(waste, "가목 1) 가)", "1차")
    assert u.action.startswith("담배꽁초")
    assert "생활폐기물을 버리거나" in u.parent_action
    assert u.basis == "법 제68조 제3항제1호"


def test_도로교통법_별표는_영향을_받지_않는다():
    """전략을 가른 뒤에도 기존 경로가 그대로인지. 건수는 test_pipeline 이 본다."""
    for slug in ("byeolpyo6", "byeolpyo7", "byeolpyo8", "byeolpyo10"):
        scheme = extract_tables.SCHEMES.get(slug, extract_tables.ROADS)
        assert scheme.strategy == "cell"
        assert scheme is extract_tables.ROADS


# --- 큐레이션 ---------------------------------------------------------------
# curation.json 쪽과 같은 규칙을 본다. 모든 행이 정확히 하나의 개념에 속하고,
# 한 개념 안에서 금액이 어긋나지 않아야 한다 (publish 가 거부한다).

@pytest.fixture(scope="module")
def curation() -> dict:
    return json.loads(CURATION.read_text(encoding="utf-8"))


def test_모든_행이_개념에_붙는다(waste, curation):
    refs = {u.ref for u in waste.units}
    rows = curation["rows"]
    assert set(rows) == refs, (
        f"매핑 없는 행 {sorted(refs - set(rows))} / "
        f"별표에 없는 행 {sorted(set(rows) - refs)}")


def test_개념이_남거나_모자라지_않는다(curation):
    concepts, used = curation["concepts"], set(curation["rows"].values())
    assert set(concepts) == used, (
        f"안 쓰는 개념 {sorted(set(concepts) - used)} / "
        f"정의 안 된 개념 {sorted(used - set(concepts))}")
    assert len(concepts) == EXPECTED_CONCEPTS


def test_한_개념_안에서_금액이_어긋나지_않는다(waste, curation):
    rows = curation["rows"]
    seen: dict[tuple[str, str], set[str]] = defaultdict(set)
    for u in waste.units:
        seen[(rows[u.ref], u.offense)].add(u.amount)
    bad = {k: sorted(v) for k, v in seen.items() if len(v) > 1}
    assert not bad, f"같은 개념에 금액이 여럿입니다: {bad}"


def test_문구가_다_있다(curation):
    for key, c in curation["concepts"].items():
        assert c["title"].strip(), key
        assert c["summary"].strip(), key
        assert 0 <= c["awareness"] <= 100, key
        assert c["audience"] in ("resident", "operator"), (key, c["audience"])
        assert c["subcategory"].strip(), key


def test_생활인_대상은_일곱_가지다(curation):
    """조문을 확인해 가른 결과다. 표만 보면 열둘로 잘못 센다.

    사목 2)·3) 은 '(사업활동과 관련하여 배출하는 경우로 한정한다)' 이고,
    자목의 법 제15조의2 는 음식물류 폐기물 '다량 배출자' 의무다.
    둘 다 일반 가정이 아니다.
    """
    res = {k for k, c in curation["concepts"].items()
           if c["audience"] == "resident"}
    assert len(res) == EXPECTED_RESIDENT, sorted(res)
    assert "discharge-household" in res          # 사목 1) 주거생활
    assert "litter-handheld" in res              # 담배꽁초
    for key in ("discharge-tenant", "discharge-tenant-shared",
                "foodwaste-ordinance"):
        assert curation["concepts"][key]["audience"] == "operator", key
