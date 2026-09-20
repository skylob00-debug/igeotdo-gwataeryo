"""별표 HWP -> 부과 단위(Unit) 목록.

부과 단위는 "금액이 하나로 정해지는 최소 단위"다. 대개는 항목(1., 1의2.)
하나가 곧 단위지만, 목마다 금액이 다른 항목도 있다.

HWP 표의 행/열/병합 정보를 그대로 쓴다. 법령 API 가 주는 별표내용(박스아트)은
셀 병합 정보가 없고 금액이 셀 안에서 세로 가운데 정렬돼 있어, 어느 목이 어느
금액을 쓰는지 알 수 없다. 대신 박스아트는 교차 검증용으로 남겨 둔다.

별표 6·8 에서 목이 표현되는 방식은 두 가지다.

  (A) 목이 각자 자기 행을 갖고, 같은 행의 금액 칸에 제 금액이 있다.
      -> 행 단위로 정확히 매핑된다. (예: 별표 6 제4호 제한속도 위반)

  (B) 항목과 목이 한 셀 안에 문단으로 들어 있다.
      금액 묶음이 하나면 모든 목이 그 금액을 쓴다.
      금액 묶음이 둘 이상이면 어느 목이 어느 묶음인지가 데이터에 없다
      (렌더링 위치로만 구분된다). 이 경우만 검수 대상으로 표시한다.
      2026-09 기준 별표 6 에 2건, 별표 8 에 0건이다.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import hwptable

ITEM_RE = re.compile(r"^(\d+(?:의\d+)?)\.\s*(.*)$", re.S)
MOK_RE = re.compile(r"^([가-하])\.\s*(.*)$", re.S)
MOK_LETTERS = set("가나다라마바사아자차카타파하")
ENUM_RE = re.compile(r"^(\d+)\)")
# 폐지된 항목. 번호만 남고 내용이 "삭제 <2014.12.31.>" 으로 바뀐다.
# 근거 법조문과 금액이 없으므로, 한 셀에 항목이 여럿일 때 짝을 맞추기 전에 걸러야 한다.
# (별표 8 제38호를 남겨 두면 제30~37호의 근거 법조문이 통째로 밀린다)
REPEALED_RE = re.compile(r"^삭제\s*<")
_WS = re.compile(r"\s+")


@dataclass(frozen=True)
class Scheme:
    """별표마다 다른 표의 생김새.

    도로교통법 별표 넷은 모두 같은 꼴이라 지금까지 상수로 박아 두고 있었다.
    생활 과태료 별표는 세 군데가 다르다.

      1. 번호 체계   1./가. 가 아니라 가./1)/가) 의 3단계다
      2. 금액 열     차종 하나가 아니라 1차/2차/3차 세 열이다
      3. 단위        셀에는 맨숫자만 있고 '만원' 은 머리글에만 있다

    셀 안에 항목을 여러 개 욱여넣는 도로교통법 별표 8 같은 구조와,
    한 행이 곧 한 항목인 구조는 읽는 방식 자체가 다르다. 한 함수에서
    둘 다 하려다 보면 잘 돌던 쪽이 깨진다. 전략을 갈라 둔다.
    """
    strategy: str = "cell"                  # "cell"(도로교통법) | "row"(생활)
    first_row: int = 2                      # 데이터가 시작하는 행
    amount_cols: tuple[tuple[int, str], ...] = ((2, ""),)   # (열 번호, 횟수 이름)
    amount_suffix: str = ""                 # 셀에 단위가 없을 때 붙인다
    # row 전략의 계층. (정규식, 참조 표기 꼴) 을 얕은 단계부터 적는다.
    levels: tuple[tuple[str, str], ...] = ()


ROADS = Scheme()

# 폐기물관리법 시행령 별표 8. 단위는 머리글의 '(단위 : 만원)' 하나뿐이다.
WASTE = Scheme(
    strategy="row",
    first_row=3,
    amount_cols=((2, "1차"), (3, "2차"), (4, "3차 이상")),
    amount_suffix="만원",
    levels=((r"^([가-하])\.\s*", "{}목"),
            (r"^(\d+)\)\s*", "{})"),
            (r"^([가-하])\)\s*", "{})")),
)

SCHEMES: dict[str, Scheme] = {"waste8": WASTE}


@dataclass
class Unit:
    """금액이 하나로 정해지는 최소 부과 단위."""
    item_no: str                    # "4"
    sub_no: str | None              # "가" (목이 없으면 None)
    action: str                     # 단위 본문 (목이면 목 본문)
    parent_action: str              # 목일 때 상위 항목 본문
    basis: str                      # 근거 법조문
    amount: str                     # 금액 원문
    row: int                        # 원본 표의 행 번호 (추적용)
    needs_review: bool = False
    review_note: str = ""
    # 위반 횟수. 생활 과태료 별표는 1차/2차/3차 열이 따로 있다.
    # 도로교통법 별표에는 없으므로 빈 값이다.
    offense: str = ""
    # 번호 체계가 '제1호 가목' 꼴이 아닌 별표용. 비면 아래 기본 표기를 쓴다.
    ref_override: str = ""

    @property
    def ref(self) -> str:
        if self.ref_override:
            return self.ref_override
        return f"제{self.item_no}호" + (f" {self.sub_no}목" if self.sub_no else "")

    @property
    def full_action(self) -> str:
        return f"{self.parent_action} / {self.action}" if self.parent_action else self.action


@dataclass
class Byeolpyo:
    slug: str
    heading: str                    # "■ 도로교통법 시행령 [별표 6] <개정 2025. 3. 18.>"
    title: str
    units: list[Unit]
    notes: list[str] = field(default_factory=list)

    @property
    def amended(self) -> str:
        m = re.search(r"<개정\s*([^>]+)>", self.heading)
        return m.group(1).strip() if m else ""

    @property
    def label(self) -> str:
        m = re.search(r"\[(별표\s*[^\]]+)\]", self.heading)
        return m.group(1) if m else self.slug

    @property
    def review_units(self) -> list[Unit]:
        return [u for u in self.units if u.needs_review]


def amount_groups(paras: list[str]) -> list[str]:
    """금액 셀의 문단들을 부과 단위별 묶음으로 나눈다.

    차종이 '1) 승합자동차등: ...' 처럼 열거되면 '1)' 에서 새 묶음이 시작된다.
    열거 기호가 아예 없으면 문단 하나가 곧 한 단위의 금액이다.
    (별표 6 제9호: '6만원'=13세 미만, '3만원'=13세 이상)

    '차종 구분 없음:' 처럼 금액 없이 차종만 있는 줄은 뒤따르는 줄들의 접두사다.
    """
    prefix = ""
    body: list[str] = []
    for p in paras:
        s = p.strip()
        if s.endswith(":"):
            prefix = s[:-1].strip() + ": "
            continue
        body.append(s if ENUM_RE.match(s) else prefix + s)

    if not any(ENUM_RE.match(p) for p in body):
        return [_WS.sub(" ", p).strip() for p in body]

    groups: list[list[str]] = []
    for p in body:
        m = ENUM_RE.match(p)
        if (m and m.group(1) == "1") or not groups:
            groups.append([])
        groups[-1].append(p)
    return [_WS.sub(" ", " ".join(g)).strip() for g in groups]


def _continues_enumeration(paras: list[str]) -> bool:
    """이 행의 금액이 앞 행 열거의 이어짐인가.

    1) 로 다시 시작하면 새 금액이고, 2) 3) 으로 시작하면 앞 행에서 잘린 것이다.
    """
    if not paras:
        return False
    m = ENUM_RE.match(paras[0])
    return bool(m) and m.group(1) != "1"


# 일반기준 셀 끝에 다음 절 머리말이 딸려 붙는다.
# ("... 감경할 필요가 있다고 인정되는 경우 2. 개별기준 (단위 : 만원)")
# 한 셀 안에 있어서 떼어지지 않는다. 앱에 그대로 내보내면 비고가 어정쩡하게 끝난다.
_NEXT_SECTION = re.compile(r"\s*\d+\.\s*개별기준.*$")


def _trim_note(text: str) -> str:
    return _NEXT_SECTION.sub("", text).strip()


def _parse_rows(slug: str, table, grid, scheme: Scheme) -> Byeolpyo:
    """한 행이 곧 한 항목인 표를 읽는다 (생활 과태료 별표).

    계층은 번호 표기로만 드러난다. 얕은 단계가 나오면 그보다 깊은 경로를
    버리고, 금액이 붙은 행을 잎으로 본다. 근거 법조문은 병합 셀이라
    상위 행에만 있으므로 단계별로 물려받는다.

    금액 열이 여럿이므로 (잎 × 비어 있지 않은 금액 열) 하나가 부과 단위다.
    """
    heading = title = ""
    notes: list[str] = []
    path: dict[int, tuple[str, str]] = {}   # 단계 -> (번호, 본문)
    bases: dict[int, str] = {}              # 단계 -> 근거 법조문
    units: list[Unit] = []

    for r in range(table.n_rows):
        c0 = grid.get((r, 0))
        if c0 is None or c0.row != r:
            continue
        text = _WS.sub(" ", " ".join(p.strip() for p in c0.paras if p.strip())).strip()
        if not text:
            continue

        # 표 위쪽의 전체 폭 셀: 머리글 / 제목 / 일반기준
        if c0.col_span == table.n_cols:
            if text.startswith("■"):
                heading = text
            elif not title:
                title = text
            else:
                notes.append(_trim_note(text))
            continue
        if r < scheme.first_row:
            continue

        level = next((i for i, (pat, _) in enumerate(scheme.levels, 1)
                      if re.match(pat, text)), None)
        if level is None:
            continue                        # 열 머리글("위반행위") 등
        mark = re.match(scheme.levels[level - 1][0], text).group(1)
        body = re.sub(scheme.levels[level - 1][0], "", text).strip()

        path[level] = (mark, body)
        for deeper in [k for k in path if k > level]:
            path.pop(deeper)
        c1 = grid.get((r, 1))
        basis_here = c1.text.strip() if c1 and c1.row == r else ""
        if basis_here:
            bases[level] = _WS.sub(" ", basis_here)
            for deeper in [k for k in bases if k > level]:
                bases.pop(deeper)

        for col, offense in scheme.amount_cols:
            cell = grid.get((r, col))
            raw = cell.text.strip() if cell else ""
            if not raw:
                continue
            steps = sorted(path)
            ref = " ".join(scheme.levels[i - 1][1].format(path[i][0]) for i in steps)
            parent = " / ".join(path[i][1] for i in steps[:-1])
            basis = bases.get(max(bases), "") if bases else ""
            units.append(Unit(
                item_no=path[steps[0]][0], sub_no=mark if level > 1 else None,
                action=body, parent_action=parent, basis=basis,
                amount=raw + scheme.amount_suffix, row=r,
                offense=offense, ref_override=ref,
                needs_review=False, review_note=""))

    return Byeolpyo(slug=slug, heading=heading, title=title,
                    units=units, notes=notes)


def parse(slug: str, raw_dir: Path, scheme: Scheme | None = None) -> Byeolpyo:
    tables, outside = hwptable.read(str(raw_dir / f"{slug}.hwp"))
    if not tables:
        raise ValueError(f"{slug}: HWP 에서 표를 찾지 못했습니다")
    table = max(tables, key=lambda t: len(t.cells))
    grid = table.grid()

    scheme = scheme or SCHEMES.get(slug, ROADS)
    if scheme.strategy == "row":
        return _parse_rows(slug, table, grid, scheme)

    heading = next((p for p in outside if p.startswith("■")), "")
    title = ""
    notes: list[str] = []
    for c in table.cells:
        if c.col_span == table.n_cols and c.text:
            if c.text.startswith("비고"):
                notes = [p for p in c.paras[1:]]
            elif not title:
                title = c.text

    # 먼저 데이터 행을 한 번에 훑는다. 뒤 행을 봐야 판단되는 경우가 있다.
    rows: list[tuple[int, list[_Entry], list[str], list[str]]] = []
    for r in range(2, table.n_rows):
        c0 = grid.get((r, 0))
        if c0 is None or c0.row != r or c0.col_span == table.n_cols:
            continue
        paras = [p for p in c0.paras if p.strip()]
        if not paras:
            continue
        c1, c2 = grid.get((r, 1)), grid.get((r, 2))
        bases = [p for p in c1.paras if p.strip()] if c1 else []
        amounts = [p for p in c2.paras if p.strip()] if c2 else []
        entries = _entries(paras)
        if not entries:
            continue
        if (rows and entries[0].no is None and rows[-1][1][-1].no
                and _continues_enumeration(amounts)):
            # 한 항목이 두 행에 걸쳐 있고 금액 열거도 잘려 있다.
            # (별표 6 제2의3호: 앞 행에 "1) 승합 4만원, 2) 승용 4만원",
            #  뒤 행에 목 다섯 개와 "3) 이륜 3만원")
            # 목이 각자 금액을 갖는 경우(별표 7 제2호)와 달리 열거가 1) 로
            # 다시 시작하지 않으므로 구분된다.
            prev_entries, prev_amounts = rows[-1][1], rows[-1][3]
            prev_entries[-1].moks += entries[0].moks
            prev_amounts.extend(amounts)
            continue
        rows.append((r, entries, bases, amounts))

    units: list[Unit] = []
    last_groups: list[str] = []     # 빈 금액 칸은 바로 위 금액을 물려받는다
    parent: _Entry | None = None    # 목이 다음 행에 오는 항목

    for i, (r, entries, bases, amounts) in enumerate(rows):
        groups = amount_groups(amounts)
        if entries[0].no is None:
            # 목만 들어 있는 행 = 앞 항목의 이어짐
            if parent is None:
                continue
            entries[0].no = parent.no
            entries[0].action = parent.action
            if not bases:
                bases = parent.bases
        else:
            nxt = rows[i + 1][1] if i + 1 < len(rows) else None
            if (len(entries) == 1 and not entries[0].moks and not groups
                    and nxt and nxt[0].no is None):
                # 이 행은 목의 상위 항목일 뿐이다. 단위를 만들지 않는다.
                parent = entries[0]
                parent.bases, parent.row = bases, r
                continue
            # 항목과 첫 목이 한 셀에 있고 나머지 목이 다음 행들에 오는 경우가 있다.
            # (별표 7 제2호: "2. 제한속도를 준수하지 않은..." + "가. 60㎞/h 초과"가
            #  한 셀에 있고 나·다·라목은 각자 행을 갖는다)
            # 뒤따르는 목만 있는 행이 붙을 수 있도록 이 행의 항목을 기억해 둔다.
            parent = entries[-1] if entries[-1].no else None
            if parent is not None:
                parent.bases = bases

        if groups:
            last_groups = groups
        else:
            groups = last_groups

        leaves = [(e, m) for e in entries for m in (e.moks or [None])]
        n = len(leaves)
        for j, (e, mok) in enumerate(leaves):
            if len(groups) == n:
                amount, note = [groups[j]], ""
            elif len(groups) <= 1:
                amount, note = groups, ""
            else:
                amount = groups
                note = (f"금액 묶음이 {len(groups)}개인데 부과 단위가 {n}개입니다. "
                        "원문에서 어느 단위가 어느 금액인지 확인한 뒤 하나만 남기세요.")
            units.append(_make(e, amount, bases, r, mok=mok, note=note,
                               idx=entries.index(e), n_entries=len(entries)))

    return Byeolpyo(slug=slug, heading=heading, title=title, units=units, notes=notes)


@dataclass
class _Entry:
    """한 셀 안의 항목 하나. 목을 가질 수도 있다."""
    no: str | None
    action: str
    moks: list[tuple[str, str]] = field(default_factory=list)
    parent: str = ""
    bases: list[str] = field(default_factory=list)
    row: int = 0


def _entries(paras: list[str]) -> list[_Entry]:
    """셀의 문단들을 항목/목 구조로 쪼갠다.

    한 셀에 항목이 여러 개 들어 있는 경우가 많다 (별표 8 에서 흔하다).
    목만 들어 있는 셀은 앞 행 항목의 이어짐이다.
    """
    out: list[_Entry] = []
    for p in paras:
        s = p.strip()
        mi = ITEM_RE.match(s)
        if mi:
            out.append(_Entry(no=mi.group(1), action=_WS.sub(" ", mi.group(2)).strip()))
            continue
        mk = MOK_RE.match(s)
        if mk and mk.group(1) in MOK_LETTERS:
            if not out:
                out.append(_Entry(no=None, action=""))
            out[-1].moks.append((mk.group(1), _WS.sub(" ", mk.group(2)).strip()))
            continue
        if not out:
            continue
        if out[-1].moks:
            letter, text = out[-1].moks[-1]
            out[-1].moks[-1] = (letter, _WS.sub(" ", f"{text} {s}").strip())
        else:
            out[-1].action = _WS.sub(" ", f"{out[-1].action} {s}").strip()
    return [e for e in out if not REPEALED_RE.match(e.action)]


def _make(entry: _Entry, groups: list[str], bases: list[str], row: int, *,
          mok: tuple[str, str] | None = None, note: str = "",
          idx: int = 0, n_entries: int = 1) -> Unit:
    # 근거 법조문이 항목 수와 같으면 항목별로 짝짓고, 아니면 통째로 쓴다
    if len(bases) == n_entries and n_entries > 1:
        basis = bases[idx]
    elif bases:
        basis = " ".join(bases) if len(bases) > 1 else bases[0]
    else:
        basis = " ".join(entry.bases)

    sub_no, action = (mok[0], mok[1]) if mok else (None, entry.action)
    parent = entry.action if mok else entry.parent
    return Unit(item_no=entry.no or "?", sub_no=sub_no, action=action,
                parent_action=parent, basis=basis.strip(),
                amount=" | ".join(groups), row=row,
                needs_review=bool(note) or not groups, review_note=note)


if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    raw = Path(__file__).parent / "raw"
    for slug in ("byeolpyo6", "byeolpyo7", "byeolpyo8", "byeolpyo10"):
        b = parse(slug, raw)
        print(f"\n===== {slug} [{b.label}] 개정 {b.amended}")
        print(f"      {b.title}")
        print(f"      단위 {len(b.units)}개, 검수대상 {len(b.review_units)}개, 비고 {len(b.notes)}줄")
        for u in b.units:
            if u.item_no in ("1", "4", "4의2"):
                print(f"   [{u.ref}] {u.full_action[:62]}")
                print(f"        근거 {u.basis} | 금액 {u.amount[:70]}")
        for u in b.review_units:
            print(f"   !! 검수 [{u.ref}] {u.review_note}")
