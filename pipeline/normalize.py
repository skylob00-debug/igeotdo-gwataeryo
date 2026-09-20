"""부과 단위(Unit) -> DB 적재용 레코드.

금액 원문("1) 승합자동차등: 8만원 2) 승용자동차등: 7만원")을 차종별 정수로 바꾼다.
파싱하지 못한 행은 버리지 않고 needs_review 로 표시해 검수 단계로 넘긴다.
"""
from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path

import extract_tables as ex

# 별표 비고에 정의된 차종 구분
VEHICLES: dict[str, str] = {
    "승합자동차등": "van",          # 승합차, 4톤 초과 화물차, 특수차, 건설기계, 노면전차
    "승용자동차등": "car",          # 승용차, 4톤 이하 화물차
    "이륜자동차등": "motorcycle",   # 이륜차, 원동기장치자전거(개인형 이동장치 제외)
    "자전거등 및 손수레등": "bicycle",
    "자전거등": "bicycle",
    "자전거": "bicycle",
    "개인형 이동장치": "pm",
    "모든 차마": "all",
    "차종 구분 없음": "all",
}

# 과태료 / 범칙금. 7·10 은 어린이·노인·장애인보호구역판이다.
KIND = {"byeolpyo6": "fine", "byeolpyo7": "fine",
        "byeolpyo8": "ticket", "byeolpyo10": "ticket",
        "waste8": "fine"}

# 별표가 속한 갈래. 앱 홈에서 운전/생활을 가르는 축이다.
CATEGORY = {"waste8": "waste"}           # 스키마 CHECK: driving | waste | etc

# 위반 횟수 표기 -> 차수. 생활 과태료 별표에만 있다.
OFFENSE = {"1차": 1, "2차": 2, "3차 이상": 3}

# 보호구역 별표는 일반 도로판보다 금액이 높다. 앱에서 구분해 보여줘야 한다.
PROTECTED_ZONE = {"byeolpyo7", "byeolpyo10"}

_ENUM_SPLIT = re.compile(r"\s*\d+\)\s*")
_AMOUNT = re.compile(r"(?:(\d+)만)?(?:(\d+)천)?(\d+)?원")
# 폐지된 항목. 번호만 남고 내용이 "삭제 <2014.12.31.>" 으로 바뀐다.
_REPEALED = re.compile(r"^삭제\s*<")


@dataclass
class Penalty:
    vehicle: str
    amount_krw: int
    surcharge_krw: int | None = None     # 괄호 안 가중 금액
    # 위반 횟수. 생활 과태료는 1/2/3차가 각각 금액이 다르다.
    # 도로교통법 별표에는 횟수 구분이 없어 전부 1 이다.
    offense_count: int = 1


@dataclass
class Record:
    id: str
    source: str
    byeolpyo: str
    kind: str
    category: str
    item_no: str
    sub_no: str | None
    ref: str
    action: str
    parent_action: str
    basis: str
    penalties: list[Penalty] = field(default_factory=list)
    raw_amount: str = ""
    penalty_formula: str = ""     # 누진 과태료처럼 정수로 안 되는 가산 규칙
    needs_review: bool = False
    review_note: str = ""
    confirmed_by: str = ""        # 사람이 확정한 경우 그 근거


def parse_amount(text: str) -> int | None:
    """'8만원' -> 80000, '1만5천원' -> 15000. 못 읽으면 None."""
    m = _AMOUNT.search(text.replace(",", "").replace(" ", ""))
    if not m or not any(m.groups()):
        return None
    man, cheon, won = (int(g) if g else 0 for g in m.groups())
    return man * 10_000 + cheon * 1_000 + won


def parse_penalties(raw: str) -> tuple[list[Penalty], str]:
    """금액 원문 -> (차종별 금액, 문제가 있으면 사유)."""
    if not raw.strip():
        return [], "금액이 비어 있습니다."
    if " | " in raw:
        return [], "금액 묶음이 둘 이상입니다."

    parts = [p.strip() for p in _ENUM_SPLIT.split(raw) if p.strip()]
    out: list[Penalty] = []
    for part in parts:
        vehicle = "all"
        body = part
        if ":" in part:
            label, body = (s.strip() for s in part.split(":", 1))
            if label not in VEHICLES:
                return [], f"모르는 차종 표기: {label!r}"
            vehicle = VEHICLES[label]

        head, _, paren = body.partition("(")
        amount = parse_amount(head)
        if amount is None:
            return [], f"금액을 읽지 못했습니다: {body!r}"
        # "5만원(6만원)" 뒤에 설명이 더 붙어 있으면 사람이 봐야 한다
        if len(_AMOUNT.findall(head)) > 1:
            return [], f"한 항목에 금액이 여럿입니다: {body!r}"
        surcharge = parse_amount(paren) if paren else None
        out.append(Penalty(vehicle=vehicle, amount_krw=amount, surcharge_krw=surcharge))

    if not out:
        return [], "금액을 읽지 못했습니다."
    seen = [p.vehicle for p in out]
    if len(seen) != len(set(seen)):
        return out, f"차종이 중복됩니다: {seen}"
    return out, ""


def slugify(source: str, unit: ex.Unit) -> str:
    no = unit.item_no.replace("의", "-")
    return f"{source}-{no}" + (f"-{unit.sub_no}" if unit.sub_no else "")


def row_id(source: str, ref: str) -> str:
    """'가목 1) 가)' -> 'waste8-가-1-가'.

    번호 체계가 제N호 가목 꼴이 아닌 별표용. 계층 표기를 그대로 남긴다.
    """
    return f"{source}-" + "-".join(t.rstrip("목)").strip() for t in ref.split())


OVERRIDES = Path(__file__).parent / "overrides.json"


def load_overrides(raw_dir: Path) -> dict[str, dict]:
    """사람이 확정한 값. 원문이 개정됐으면 쓰지 않고 멈춘다."""
    if not OVERRIDES.exists():
        return {}
    data = json.loads(OVERRIDES.read_text(encoding="utf-8"))
    manifest = json.loads((raw_dir / "manifest.json").read_text(encoding="utf-8"))
    for slug, digest in data.get("source_sha256", {}).items():
        actual = manifest["byeolpyo"].get(slug, {}).get("sha256")
        if actual != digest:
            raise SystemExit(
                f"{slug} 원문이 확정 당시와 다릅니다. 개정 내용을 확인하고 "
                f"pipeline/overrides.json 을 다시 검토한 뒤 해시를 갱신하세요.\n"
                f"  확정 당시: {digest}\n  현재:      {actual}")
    return data.get("records", {})


def _build_rows(slug: str, b: ex.Byeolpyo) -> list[Record]:
    """행 단위 별표(생활 과태료). 한 행위의 1·2·3차를 한 레코드로 묶는다.

    차종 축이 없으므로 vehicle 은 'none' 하나다. 대신 offense_count 가
    금액을 가른다. overrides 는 쓰지 않는다 — 지금 검수 대상이 0건이고,
    필요해지면 도로교통법 쪽과 같은 방식으로 붙이면 된다.
    """
    groups: dict[str, list[ex.Unit]] = {}
    for u in b.units:
        groups.setdefault(u.ref, []).append(u)

    out: list[Record] = []
    for ref, units in groups.items():
        first = units[0]
        penalties: list[Penalty] = []
        problem = ""
        for u in sorted(units, key=lambda x: OFFENSE.get(x.offense, 0)):
            amount = parse_amount(u.amount)
            if amount is None:
                problem = f"금액을 읽지 못했습니다: {u.amount!r}"
                break
            penalties.append(Penalty(vehicle="none", amount_krw=amount,
                                     offense_count=OFFENSE[u.offense]))
        tokens = ref.split()
        out.append(Record(
            id=row_id(slug, ref), source=slug, byeolpyo=b.label,
            kind=KIND[slug], category=CATEGORY.get(slug, "driving"),
            item_no=tokens[0].rstrip("목)"),
            sub_no="-".join(t.rstrip(")") for t in tokens[1:]) or None,
            ref=ref, action=first.action, parent_action=first.parent_action,
            basis=first.basis, penalties=[] if problem else penalties,
            raw_amount=" / ".join(f"{u.offense} {u.amount}" for u in units),
            needs_review=bool(problem), review_note=problem,
        ))
    return out


def build(slug: str, raw_dir: Path) -> tuple[list[Record], ex.Byeolpyo]:
    b = ex.parse(slug, raw_dir)
    if ex.SCHEMES.get(slug, ex.ROADS).strategy == "row":
        return _build_rows(slug, b), b

    overrides = load_overrides(raw_dir)
    used: set[str] = set()
    out: list[Record] = []

    for u in b.units:
        if _REPEALED.match(u.action):
            continue        # 폐지된 항목은 싣지 않는다
        rid = slugify(slug, u)
        fix = overrides.get(rid)
        amount = fix["amount"] if fix else u.amount
        if fix:
            used.add(rid)

        penalties, problem = parse_penalties(amount)
        note = "" if fix else "; ".join(n for n in (u.review_note, problem) if n)
        if fix and problem:
            note = f"확정값도 읽지 못했습니다: {problem}"

        out.append(Record(
            id=rid, source=slug, byeolpyo=b.label, kind=KIND[slug],
            category=CATEGORY.get(slug, "driving"),
            item_no=u.item_no, sub_no=u.sub_no, ref=u.ref,
            action=u.action, parent_action=u.parent_action, basis=u.basis,
            penalties=penalties, raw_amount=amount,
            penalty_formula=(fix or {}).get("formula", ""),
            needs_review=bool(note), review_note=note,
            confirmed_by=(fix or {}).get("reason", ""),
        ))

    stale = {k for k in overrides if k.startswith(f"{slug}-")} - used
    if stale:
        raise SystemExit(
            f"overrides.json 에 더 이상 존재하지 않는 id 가 있습니다: {sorted(stale)}")
    return out, b


SLUGS = ("byeolpyo6", "byeolpyo7", "byeolpyo8", "byeolpyo10", "waste8")


def main() -> None:
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    raw = Path(__file__).parent / "raw"
    out_dir = Path(__file__).parent / "out"
    out_dir.mkdir(parents=True, exist_ok=True)

    payload: dict[str, object] = {"byeolpyo": {}, "records": []}
    for slug in SLUGS:
        records, b = build(slug, raw)
        payload["byeolpyo"][slug] = {
            "label": b.label, "title": b.title,
            "amended": b.amended, "notes": b.notes,
        }
        payload["records"] += [asdict(r) for r in records]
        need = [r for r in records if r.needs_review]
        dropped = len(b.units) - len(records)
        print(f"{slug} [{b.label}] 개정 {b.amended}: "
              f"{len(records)}건, 검수 {len(need)}건, 폐지 제외 {dropped}건")
        for r in need:
            print(f"   - {r.ref}: {r.review_note}")

    path = out_dir / "violations.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    total = len(payload["records"])
    need = sum(1 for r in payload["records"] if r["needs_review"])
    print(f"\n총 {total}건 (검수 {need}건) -> {path}")


if __name__ == "__main__":
    main()
