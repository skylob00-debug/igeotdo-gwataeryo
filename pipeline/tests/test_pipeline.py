"""파이프라인 검증.

두 종류를 본다.
  1. 스냅샷 - 원문(sha256)이 그대로일 때 추출 결과 건수가 변하지 않는지.
     파서를 고치다 조용히 항목을 흘리는 일을 막는다.
  2. 실측 대조 - 공개적으로 잘 알려진 금액이 맞게 나오는지.
     예: 신호위반 승용차는 범칙금 6만원 / 과태료 7만원.

원문이 개정되면 1번이 깨진다. 그때는 검수 후 기대값을 갱신한다.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import normalize

RAW = Path(__file__).resolve().parents[1] / "raw"

# 원문 sha256 - 개정되면 달라진다 (pipeline/raw/manifest.json 과 맞춰 둔다)
EXPECTED_SOURCE = {
    "byeolpyo6": "03465b6f0823c41278b5a18a3080108886437d6e1344960fa36435c0cb80ce12",
    "byeolpyo7": "7c487a57869f9e09ec1e1d9c71ac1ab4641e6110c09097b486ee640a0371aa40",
    "byeolpyo8": "2670a4aa15f6b12494f2d95a0b3cae89bbf5c7370e28f87fc9f97f0492e3af0b",
    "byeolpyo10": "e478fb7f1882991239817f8dc3610289260afa243d041e719463612f921fd3a6",
}

# (전체 건수, 검수 필요 건수)
EXPECTED_COUNTS = {
    "byeolpyo6": (72, 0),
    "byeolpyo7": (7, 0),      # 어린이·노인·장애인보호구역 과태료
    "byeolpyo8": (88, 0),
    "byeolpyo10": (16, 0),    # 보호구역 범칙금
}


@pytest.fixture(scope="module")
def records() -> dict[str, list[normalize.Record]]:
    return {slug: normalize.build(slug, RAW)[0] for slug in EXPECTED_COUNTS}


def _find(records, slug: str, ref: str) -> normalize.Record:
    hits = [r for r in records[slug] if r.ref == ref]
    assert len(hits) == 1, f"{slug} {ref}: {len(hits)}건 (1건이어야 함)"
    return hits[0]


def _amount(rec: normalize.Record, vehicle: str) -> int:
    hits = [p.amount_krw for p in rec.penalties if p.vehicle == vehicle]
    assert len(hits) == 1, f"{rec.ref}: 차종 {vehicle} 이 {len(hits)}건"
    return hits[0]


def test_원문이_바뀌지_않았다():
    manifest = json.loads((RAW / "manifest.json").read_text(encoding="utf-8"))
    for slug, digest in EXPECTED_SOURCE.items():
        actual = manifest["byeolpyo"][slug]["sha256"]
        assert actual == digest, (
            f"{slug} 원문이 바뀌었습니다. 개정 여부를 확인하고 "
            f"검수 후 기대값을 갱신하세요. ({actual})")


@pytest.mark.parametrize("slug", sorted(EXPECTED_COUNTS))
def test_추출_건수(records, slug):
    total, need = EXPECTED_COUNTS[slug]
    assert len(records[slug]) == total
    assert sum(1 for r in records[slug] if r.needs_review) == need


@pytest.mark.parametrize("slug", sorted(EXPECTED_COUNTS))
def test_id가_유일하다(records, slug):
    ids = [r.id for r in records[slug]]
    assert len(ids) == len(set(ids))


@pytest.mark.parametrize("slug", sorted(EXPECTED_COUNTS))
def test_검수대상이_아니면_금액과_근거가_있다(records, slug):
    for r in records[slug]:
        if r.needs_review:
            assert r.review_note, f"{r.ref}: 검수 사유가 비어 있습니다"
            continue
        assert r.penalties, f"{r.ref}: 금액이 없습니다"
        assert r.basis, f"{r.ref}: 근거 법조문이 없습니다"
        assert r.action, f"{r.ref}: 위반행위가 비어 있습니다"
        for p in r.penalties:
            assert 1_000 <= p.amount_krw <= 20_000_000, f"{r.ref}: {p}"


def test_범칙금_실측(records):
    """도로교통법 시행령 별표 8 (운전자 범칙금)."""
    속도60 = _find(records, "byeolpyo8", "제1호")
    assert "속도위반(60㎞/h 초과)" in 속도60.action
    assert _amount(속도60, "van") == 130_000
    assert _amount(속도60, "car") == 120_000
    assert _amount(속도60, "motorcycle") == 80_000

    신호 = _find(records, "byeolpyo8", "제4호")
    assert 신호.action == "신호·지시 위반"
    assert _amount(신호, "car") == 60_000          # 널리 알려진 값
    assert _amount(신호, "van") == 70_000
    assert _amount(신호, "motorcycle") == 40_000
    assert _amount(신호, "bicycle") == 30_000


def test_과태료_실측(records):
    """도로교통법 시행령 별표 6 (고용주등 과태료)."""
    신호 = _find(records, "byeolpyo6", "제1호")
    assert _amount(신호, "car") == 70_000          # 범칙금 6만원 / 과태료 7만원
    assert _amount(신호, "van") == 80_000

    속도60 = _find(records, "byeolpyo6", "제4호 가목")
    assert 속도60.action == "60㎞/h 초과"
    assert "제한속도" in 속도60.parent_action
    assert _amount(속도60, "van") == 140_000
    assert _amount(속도60, "car") == 130_000
    assert _amount(속도60, "motorcycle") == 90_000

    속도20이하 = _find(records, "byeolpyo6", "제4호 라목")
    assert 속도20이하.action == "20㎞/h 이하"
    assert _amount(속도20이하, "car") == 40_000


def test_2시간_이상_주차_가중금액(records):
    """별표 6 비고 4: 괄호 안은 같은 장소 2시간 이상 정차·주차 위반에 적용."""
    주정차 = _find(records, "byeolpyo6", "제6호")
    car = next(p for p in 주정차.penalties if p.vehicle == "car")
    assert car.amount_krw == 40_000
    assert car.surcharge_krw == 50_000
    van = next(p for p in 주정차.penalties if p.vehicle == "van")
    assert (van.amount_krw, van.surcharge_krw) == (50_000, 60_000)


def test_목별_금액이_1대1로_갈린다(records):
    """열거 기호 없이 문단만 나열된 금액도 목별로 갈라야 한다."""
    가 = _find(records, "byeolpyo6", "제9호 가목")      # 동승자 13세 미만
    나 = _find(records, "byeolpyo6", "제9호 나목")      # 동승자 13세 이상
    assert 가.action == "동승자가 13세 미만인 경우"
    assert _amount(가, "all") == 60_000
    assert _amount(나, "all") == 30_000

    교육가 = _find(records, "byeolpyo8", "제67호 가목")
    교육나 = _find(records, "byeolpyo8", "제67호 나목")
    assert _amount(교육가, "all") == 150_000       # '차종 구분 없음:' 라벨 처리
    assert _amount(교육나, "all") == 100_000


def test_한_셀에_항목이_여럿이면_근거를_짝지어_붙인다(records):
    """폐지 항목이 섞여 있어도 근거 법조문이 밀리지 않아야 한다.

    별표 8 제30~38호는 한 셀에 있고 제38호가 '삭제'라 근거가 하나 적다.
    """
    assert _find(records, "byeolpyo8", "제30호").basis == "제33조"
    assert _find(records, "byeolpyo8", "제34호").basis == "제48조제1항"
    assert _find(records, "byeolpyo8", "제37호").basis == "제49조제1항제12호"
    assert not [r for r in records["byeolpyo8"] if r.item_no == "38"]


def test_사람이_확정한_값(records):
    """자동으로 못 풀어 overrides.json 에 확정해 둔 9건.

    근거는 두 가지가 일치한다.
      - 과태료 = 같은 위반의 범칙금(별표 8) + 1만원
      - 법제처 별표내용(박스아트) 렌더링에서 금액 묶음이 찍힌 줄 위치
    """
    # 별표 6 제4의2호: 가·나·다(제18/21/22조)는 8/7/5만, 라(제62조)만 6/5/4만
    for mok in "가나다":
        r = _find(records, "byeolpyo6", f"제4의2호 {mok}목")
        assert (_amount(r, "van"), _amount(r, "car"), _amount(r, "motorcycle")) ==             (80_000, 70_000, 50_000), f"제4의2호 {mok}목"
        assert r.confirmed_by
    라 = _find(records, "byeolpyo6", "제4의2호 라목")
    assert (_amount(라, "van"), _amount(라, "car"), _amount(라, "motorcycle")) ==         (60_000, 50_000, 40_000)

    # 별표 6 제6의4호: 가(승차인원)만 8/7/5만, 나·다·라는 6/5/4만
    가 = _find(records, "byeolpyo6", "제6의4호 가목")
    assert (_amount(가, "van"), _amount(가, "car")) == (80_000, 70_000)
    for mok in "나다라":
        r = _find(records, "byeolpyo6", f"제6의4호 {mok}목")
        assert (_amount(r, "van"), _amount(r, "car")) == (60_000, 50_000), f"제6의4호 {mok}목"


def test_누진_과태료는_기준금액과_가산규칙으로_나눈다(records):
    나 = _find(records, "byeolpyo6", "제10의3호 나목")
    assert _amount(나, "all") == 100_000
    assert "3일을 초과할 때마다" in 나.penalty_formula
    # 가목·다목은 정액이라 가산 규칙이 없다
    assert _find(records, "byeolpyo6", "제10의3호 가목").penalty_formula == ""
    assert _amount(_find(records, "byeolpyo6", "제10의3호 다목"), "all") == 5_000_000


def test_확정값은_원문_해시에_묶여_있다():
    """별표가 개정되면 확정값을 그대로 쓰지 않고 멈춰야 한다."""
    import json as _json
    data = _json.loads((RAW.parent / "overrides.json").read_text(encoding="utf-8"))
    manifest = _json.loads((RAW / "manifest.json").read_text(encoding="utf-8"))
    for slug, digest in data["source_sha256"].items():
        assert manifest["byeolpyo"][slug]["sha256"] == digest
    for rid, fix in data["records"].items():
        assert fix.get("reason"), f"{rid}: 확정 근거가 비어 있습니다"
        assert fix.get("amount"), f"{rid}: 확정 금액이 비어 있습니다"


def test_보호구역은_일반도로보다_비싸다(records):
    """별표 7·10 은 어린이·노인·장애인보호구역판이다.

    '몰랐다가 무는' 앱의 핵심 데이터라 일반 도로판과 나란히 못 박아 둔다.
    """
    # 신호·지시 위반 승용차
    assert _amount(_find(records, "byeolpyo6", "제1호"), "car") == 70_000
    assert _amount(_find(records, "byeolpyo7", "제1호"), "car") == 130_000
    assert _amount(_find(records, "byeolpyo8", "제4호"), "car") == 60_000
    assert _amount(_find(records, "byeolpyo10", "제1호"), "car") == 120_000   # 정확히 2배

    # 속도위반 60㎞/h 초과 승용차
    assert _amount(_find(records, "byeolpyo6", "제4호 가목"), "car") == 130_000
    assert _amount(_find(records, "byeolpyo7", "제2호 가목"), "car") == 160_000
    assert _amount(_find(records, "byeolpyo8", "제1호"), "car") == 120_000
    assert _amount(_find(records, "byeolpyo10", "제3호 가목"), "car") == 150_000


def test_보호구역은_어린이와_노인장애인을_나눈다(records):
    """주정차 위반은 같은 별표 안에서도 구역에 따라 금액이 다르다."""
    for slug, 어린이, 노인 in (("byeolpyo7", 120_000, 80_000),
                             ("byeolpyo10", 120_000, 80_000)):
        가 = _find(records, slug, "제3호 가목" if slug == "byeolpyo7" else "제6호 가목")
        나 = _find(records, slug, "제3호 나목" if slug == "byeolpyo7" else "제6호 나목")
        assert "어린이보호구역" in 가.action
        assert "노인" in 나.action
        assert _amount(가, "car") == 어린이, slug
        assert _amount(나, "car") == 노인, slug


def test_두_행에_걸친_금액_열거를_잇는다(records):
    """별표 6 제2의3호는 앞 행에 1)2), 뒤 행에 목 다섯 개와 3) 이 있다.

    잇지 않으면 이륜자동차 금액이 통째로 빠진다.
    """
    for mok in "가나다라마":
        r = _find(records, "byeolpyo6", f"제2의3호 {mok}목")
        assert (_amount(r, "van"), _amount(r, "car"), _amount(r, "motorcycle")) ==             (40_000, 40_000, 30_000), f"제2의3호 {mok}목"


def test_금액_문자열_파싱():
    assert normalize.parse_amount("8만원") == 80_000
    assert normalize.parse_amount("10만원") == 100_000
    assert normalize.parse_amount("1만5천원") == 15_000
    assert normalize.parse_amount("500원") == 500
    assert normalize.parse_amount("없음") is None


def test_모르는_차종은_검수로_넘긴다():
    penalties, problem = normalize.parse_penalties("1) 우주선: 5만원")
    assert penalties == []
    assert "모르는 차종" in problem
