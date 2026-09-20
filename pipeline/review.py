"""검수용 CSV 출력.

추출 결과를 사람이 원문과 대조할 수 있게 표로 뽑는다.
검수가 필요한 행이 위로 오고, 직전 결과가 있으면 무엇이 바뀌었는지도 표시한다.

    python pipeline/review.py               # out/review.csv 생성
    python pipeline/review.py --snapshot    # 현재 결과를 다음 비교 기준으로 저장
    python pipeline/review.py --slug waste8 # 아직 적재 전인 별표를 추출 단계에서 검수

--slug 은 normalize 를 거치지 않는다. 생활 과태료처럼 스키마가 아직 없는
별표를 사람이 먼저 훑어보기 위한 것이다. 적재 대상이 되면 위쪽 경로로 옮긴다.

엑셀에서 한글이 깨지지 않도록 UTF-8 BOM 으로 쓴다.
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

import normalize

OUT = Path(__file__).parent / "out"
RAW = Path(__file__).parent / "raw"
CURRENT = OUT / "violations.json"
SNAPSHOT = OUT / "violations.prev.json"

COLUMNS = ["상태", "변경", "id", "출처", "조문", "종류", "위반행위", "상위항목",
           "근거 법조문", "금액", "가산 규칙", "금액 원문", "검수 사유", "확정 근거"]

VEHICLE_LABEL = {"van": "승합", "car": "승용", "motorcycle": "이륜",
                 "bicycle": "자전거", "pm": "PM", "all": "전차종"}


def format_penalties(record: dict) -> str:
    out = []
    for p in record["penalties"]:
        label = VEHICLE_LABEL.get(p["vehicle"], p["vehicle"])
        text = f"{label} {p['amount_krw']:,}원"
        if p["surcharge_krw"]:
            text += f" (2시간↑ {p['surcharge_krw']:,}원)"
        out.append(text)
    return " / ".join(out)


def load_snapshot() -> dict[str, dict]:
    if not SNAPSHOT.exists():
        return {}
    data = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    return {r["id"]: r for r in data["records"]}


def diff_mark(record: dict, before: dict[str, dict]) -> str:
    if not before:
        return ""
    old = before.get(record["id"])
    if old is None:
        return "신규"
    if old["penalties"] != record["penalties"]:
        return "금액 변경"
    if old["action"] != record["action"] or old["basis"] != record["basis"]:
        return "문구 변경"
    return ""


def build_payload() -> dict:
    payload: dict = {"byeolpyo": {}, "records": []}
    from dataclasses import asdict
    for slug in normalize.SLUGS:
        records, b = normalize.build(slug, RAW)
        payload["byeolpyo"][slug] = {"label": b.label, "title": b.title,
                                     "amended": b.amended, "notes": b.notes}
        payload["records"] += [asdict(r) for r in records]
    return payload


def write_extract_csv(slug: str) -> None:
    """적재 전 별표를 추출 단계 그대로 뽑는다.

    위반 횟수(1차/2차/3차)는 열로 편다. 원문 표와 같은 모양이라야
    사람이 눈으로 대조할 수 있다. 267줄짜리 세로 목록은 대조가 안 된다.
    """
    import extract_tables

    b = extract_tables.parse(slug, RAW)
    offenses = [o for _, o in extract_tables.SCHEMES[slug].amount_cols]

    leaves: dict[str, dict] = {}
    for u in b.units:
        row = leaves.setdefault(u.ref, {
            "ref": u.ref, "action": u.action, "parent": u.parent_action,
            "basis": u.basis, "row": u.row,
            "review": u.needs_review, "note": u.review_note, "amounts": {},
        })
        row["amounts"][u.offense] = u.amount
        row["review"] = row["review"] or u.needs_review
        row["note"] = row["note"] or u.review_note

    rows = sorted(leaves.values(), key=lambda r: (not r["review"], r["row"]))
    path = OUT / f"review_{slug}.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["상태", "조문", "위반행위", "상위항목", "근거 법조문",
                    *offenses, "원본 행", "검수 사유"])
        for r in rows:
            w.writerow(["검수" if r["review"] else "", r["ref"], r["action"],
                        r["parent"], r["basis"],
                        *[r["amounts"].get(o, "") for o in offenses],
                        r["row"], r["note"]])

    need = sum(1 for r in rows if r["review"])
    varies = sum(1 for r in rows
                 if len({r["amounts"].get(o, "") for o in offenses}) > 1)
    print(f"{b.label} {b.title}")
    print(f"  개정 {b.amended} / 비고 {len(b.notes)}덩어리")
    print(f"  행위 {len(rows)}건 (금액 {len(b.units)}건), 검수 필요 {need}건")
    print(f"  위반 횟수에 따라 금액이 달라지는 행위 {varies}건")
    print(f"-> {path}")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    OUT.mkdir(parents=True, exist_ok=True)

    if "--slug" in sys.argv:
        write_extract_csv(sys.argv[sys.argv.index("--slug") + 1])
        return

    if "--snapshot" in sys.argv:
        if not CURRENT.exists():
            raise SystemExit("먼저 python pipeline/normalize.py 를 실행하세요")
        SNAPSHOT.write_text(CURRENT.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"현재 결과를 비교 기준으로 저장했습니다 -> {SNAPSHOT}")
        return

    payload = build_payload()
    before = load_snapshot()
    rows = payload["records"]
    # 검수 대상과 변경된 행이 위로 오게
    rows.sort(key=lambda r: (not r["needs_review"], not diff_mark(r, before),
                             not r["confirmed_by"], r["id"]))

    path = OUT / "review.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(COLUMNS)
        for r in rows:
            w.writerow([
                "검수" if r["needs_review"] else ("확정" if r["confirmed_by"] else ""),
                diff_mark(r, before),
                r["id"], r["byeolpyo"], r["ref"],
                "과태료" if r["kind"] == "fine" else "범칙금",
                r["action"], r["parent_action"], r["basis"],
                format_penalties(r), r["penalty_formula"],
                r["raw_amount"], r["review_note"], r["confirmed_by"],
            ])

    need = sum(1 for r in rows if r["needs_review"])
    fixed = sum(1 for r in rows if r["confirmed_by"])
    changed = sum(1 for r in rows if diff_mark(r, before))
    print(f"{len(rows)}건 -> {path}")
    print(f"  검수 필요 {need}건, 사람이 확정 {fixed}건"
          + (f", 직전 대비 변경 {changed}건" if before else
             " (비교 기준 없음: --snapshot 으로 만들 수 있습니다)"))
    for r in rows:
        if r["needs_review"]:
            print(f"   [{r['byeolpyo']} {r['ref']}] {r['review_note']}")


if __name__ == "__main__":
    main()
