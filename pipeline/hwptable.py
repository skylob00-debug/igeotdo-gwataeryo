"""HWP5 BodyText 에서 표를 셀 단위로 읽는다.

별표의 금액 셀은 여러 행에 걸쳐 병합돼 있다. 어느 위반행위가 어느 금액을
쓰는지는 이 병합 정보가 있어야 정확히 알 수 있다.
법령 API 가 주는 별표내용(박스아트)에는 병합 정보가 없고 텍스트가 셀 안에서
세로 가운데 정렬돼 있어, 금액이 시작되는 줄만 보고는 범위를 알 수 없다.

참고: HWP 5.0 파일 형식
  레코드 헤더 4바이트 = tagID(10bit) | level(10bit) | size(12bit)
  HWPTAG_TABLE(77)       : UINT32 속성, UINT16 nRows, UINT16 nCols,
                           INT16 cellSpacing, INT16 inMargin[4], UINT16 rowSize[nRows]
  HWPTAG_LIST_HEADER(72) : INT32 nParas, UINT32 속성,
                           (표 셀) UINT16 col, row, colSpan, rowSpan, UINT32 width, height
  HWPTAG_PARA_TEXT(67)   : UTF-16LE 본문 (제어문자 포함)
"""
from __future__ import annotations

import struct
import zlib
from dataclasses import dataclass, field

import olefile

HWPTAG_PARA_TEXT = 67
HWPTAG_LIST_HEADER = 72
HWPTAG_TABLE = 77

# PARA_TEXT 안의 제어문자 폭 (wchar 단위)
_CTRL_1 = {0, 10, 13, 24, 25, 26, 27, 28, 29, 30, 31}
_CTRL_8 = {1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23}


@dataclass
class Cell:
    row: int
    col: int
    row_span: int
    col_span: int
    paras: list[str] = field(default_factory=list)

    @property
    def text(self) -> str:
        return "\n".join(p for p in self.paras if p)


@dataclass
class Table:
    n_rows: int
    n_cols: int
    cells: list[Cell]

    def grid(self) -> dict[tuple[int, int], Cell]:
        """병합을 펼친 좌표 -> 셀. 병합된 자리는 같은 Cell 을 가리킨다."""
        out: dict[tuple[int, int], Cell] = {}
        for c in self.cells:
            for r in range(c.row, c.row + c.row_span):
                for k in range(c.col, c.col + c.col_span):
                    out[(r, k)] = c
        return out


def _records(data: bytes):
    pos = 0
    while pos + 4 <= len(data):
        (header,) = struct.unpack("<I", data[pos:pos + 4])
        pos += 4
        tag = header & 0x3FF
        size = (header >> 20) & 0xFFF
        if size == 0xFFF:
            (size,) = struct.unpack("<I", data[pos:pos + 4])
            pos += 4
        yield tag, data[pos:pos + size]
        pos += size


def decode_para(payload: bytes) -> str:
    """PARA_TEXT 페이로드를 텍스트로. 제어문자는 건너뛴다."""
    n = len(payload) // 2
    units = struct.unpack(f"<{n}H", payload[:n * 2])
    out: list[str] = []
    i = 0
    while i < n:
        c = units[i]
        if c in _CTRL_8:
            i += 8
        elif c in _CTRL_1:
            if c in (30, 31):        # nbsp / 고정폭 공백은 살린다
                out.append(" ")
            i += 1
        else:
            out.append(chr(c))
            i += 1
    return "".join(out)


def _sections(hwp_path: str):
    ole = olefile.OleFileIO(hwp_path)
    try:
        (flags,) = struct.unpack("<I", ole.openstream("FileHeader").read()[36:40])
        if flags & 2:
            raise ValueError("암호화된 HWP 는 처리할 수 없습니다")
        compressed = bool(flags & 1)
        names = sorted(
            ("/".join(s) for s in ole.listdir() if s[0] == "BodyText"),
            key=lambda p: int(p.rsplit("Section", 1)[-1]),
        )
        for name in names:
            raw = ole.openstream(name).read()
            yield zlib.decompress(raw, -15) if compressed else raw
    finally:
        ole.close()


def read(hwp_path: str) -> tuple[list[Table], list[str]]:
    """(표 목록, 표 바깥 문단 목록) 반환."""
    tables: list[Table] = []
    outside: list[str] = []

    for data in _sections(hwp_path):
        pending: Table | None = None   # 셀을 아직 다 못 받은 표
        expected = 0
        cell: Cell | None = None

        for tag, payload in _records(data):
            if tag == HWPTAG_TABLE:
                attr, n_rows, n_cols = struct.unpack("<IHH", payload[:8])
                off = 8 + 2 + 8        # cellSpacing(2) + inMargin(4*2)
                row_size = struct.unpack(f"<{n_rows}H", payload[off:off + n_rows * 2])
                pending = Table(n_rows=n_rows, n_cols=n_cols, cells=[])
                expected = sum(row_size)
                cell = None

            elif tag == HWPTAG_LIST_HEADER and pending is not None:
                col, row, col_span, row_span = struct.unpack("<4H", payload[8:16])
                cell = Cell(row=row, col=col,
                            row_span=max(row_span, 1), col_span=max(col_span, 1))
                pending.cells.append(cell)

            elif tag == HWPTAG_PARA_TEXT:
                text = decode_para(payload).strip()
                if pending is not None and cell is not None:
                    if text:
                        cell.paras.append(text)
                elif text:
                    outside.append(text)

            if pending is not None and len(pending.cells) == expected and expected:
                # 마지막 셀의 문단까지 다 받으려면 다음 레코드를 더 봐야 하므로
                # 표 종료는 다음 TABLE/섹션 끝에서 처리한다.
                pass

        if pending is not None:
            tables.append(pending)

    return tables, outside


if __name__ == "__main__":
    import sys
    sys.stdout.reconfigure(encoding="utf-8")
    path = sys.argv[1] if len(sys.argv) > 1 else "pipeline/raw/byeolpyo6.hwp"
    tbs, outside = read(path)
    print("표 바깥 문단:", outside[:3])
    for t in tbs:
        print(f"\n표: {t.n_rows}행 x {t.n_cols}열, 셀 {len(t.cells)}개")
        spans = [c for c in t.cells if c.row_span > 1 or c.col_span > 1]
        print(f"  병합 셀 {len(spans)}개")
        g = t.grid()
        for r in range(min(t.n_rows, 8)):
            row = []
            for c in range(t.n_cols):
                cl = g.get((r, c))
                mark = f"[{cl.row}:{cl.row_span}]" if cl else "----"
                row.append(f"{mark}{(cl.text.replace(chr(10), ' / ')[:26] if cl else '')}")
            print("   ", " | ".join(row))
