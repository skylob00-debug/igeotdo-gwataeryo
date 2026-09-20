"""대상 법령 본문을 받아 별표의 원문(박스아트 표)과 HWP 원본을 저장한다.

PDF 를 받아 파싱하는 대신 법령 본문조회 API 의 <별표내용> 을 쓴다.
셀 경계가 박스 문자로 명시돼 있어 좌표 추정이 필요 없고, 바이너리 의존성도 없다.

법령이 둘 이상이다. manifest 의 최상위 키(law_name/mst/enforce_date)는
도로교통법 시행령을 가리킨 채로 둔다 — publish.py 가 그 값을 모든 sources 행에
쓰고 있어서, 지금 바꾸면 적재가 깨진다. 새 법령은 manifest["laws"] 아래에만
쌓아 두고, 생활 과태료를 실제로 적재할 때 publish 쪽과 함께 정리한다.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

import requests

import lawapi

RAW = Path(__file__).parent / "raw"

# 대상. 법령명 -> {(별표번호, 가지번호): 슬러그}
LAWS: dict[str, dict[tuple[str, str], str]] = {
    "도로교통법 시행령": {
        ("0006", "00"): "byeolpyo6",    # 과태료의 부과기준
        ("0007", "00"): "byeolpyo7",    # 어린이·노인·장애인보호구역에서의 과태료 부과기준
        ("0008", "00"): "byeolpyo8",    # 범칙행위 및 범칙금액(운전자)
        ("0010", "00"): "byeolpyo10",   # 보호구역에서의 범칙행위 및 범칙금액
    },
    # 생활 과태료 1단계. 전국 공통이라 조례를 보지 않아도 된다.
    # 표 구조가 다르다 — 차종 대신 위반 횟수(1차/2차/3차) 열이다.
    "폐기물관리법 시행령": {
        ("0008", "00"): "waste8",       # 과태료의 부과기준
    },
}

# manifest 최상위 키가 가리키는 법령. publish.py 가 아직 이것만 안다.
LEGACY_LAW = "도로교통법 시행령"

# OLE 복합 문서 시그니처 (HWP5 원본인지 확인용)
OLE_MAGIC = bytes([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])


def _cdata(s: str) -> str:
    return re.sub(r"<!\[CDATA\[|\]\]>", "", s)


def _tag(block: str, name: str) -> str:
    m = re.search(rf"<{name}>(.*?)</{name}>", block, flags=re.S)
    return _cdata(m.group(1)).strip() if m else ""


def _download_hwp(link: str, slug: str) -> str:
    """별표 HWP 원본을 내려받고 sha256 을 돌려준다."""
    if not link:
        raise SystemExit(f"{slug}: 별표서식파일링크가 없습니다")
    r = requests.get("https://www.law.go.kr" + link,
                     headers=lawapi.HEADERS, timeout=60)
    r.raise_for_status()
    if r.content[:8] != OLE_MAGIC:
        raise SystemExit(f"{slug}: HWP(OLE) 파일이 아닙니다 - {r.content[:8]!r}")
    (RAW / f"{slug}.hwp").write_bytes(r.content)
    return hashlib.sha256(r.content).hexdigest()


def find_mst(law_name: str) -> tuple[str, str, str]:
    """(MST, 공포일자, 시행일자) 반환."""
    xml = lawapi.search_law(law_name, display=20)
    for blk in re.findall(r"<law id=\"\d+\">(.*?)</law>", xml, flags=re.S):
        if _tag(blk, "법령명한글") == law_name:
            return _tag(blk, "법령일련번호"), _tag(blk, "공포일자"), _tag(blk, "시행일자")
    raise SystemExit(f"'{law_name}' 을(를) 목록에서 찾지 못했습니다")


def fetch_law(law_name: str, targets: dict[tuple[str, str], str]) -> dict:
    """한 법령의 대상 별표를 모두 받아 그 법령 몫의 manifest 조각을 돌려준다."""
    mst, promul, enforce = find_mst(law_name)
    print(f"{law_name}: MST={mst} 공포={promul} 시행={enforce}")

    body = lawapi.law_body(mst)
    part = {"law_name": law_name, "mst": mst,
            "promulgation_date": promul, "enforce_date": enforce,
            "byeolpyo": {}}

    for unit in re.findall(r"<별표단위[^>]*>(.*?)</별표단위>", body, flags=re.S):
        key = (_tag(unit, "별표번호"), _tag(unit, "별표가지번호"))
        slug = targets.get(key)
        if not slug:
            continue
        content = _tag(unit, "별표내용")
        if not content:
            print(f"  !! {slug}: 별표내용이 비어 있습니다")
            continue
        (RAW / f"{slug}.txt").write_text(content, encoding="utf-8")
        digest = hashlib.sha256(content.encode("utf-8")).hexdigest()

        # 박스아트는 셀 구조가 정확하지만 줄바꿈에서 띄어쓰기가 소실된다.
        # 올바른 표기는 HWP 원본에서 가져오므로 함께 받아 둔다.
        hwp_digest = _download_hwp(_tag(unit, "별표서식파일링크"), slug)

        part["byeolpyo"][slug] = {
            "byeolpyo_no": key[0], "branch_no": key[1],
            "title": _tag(unit, "별표제목"),
            "sha256": digest, "chars": len(content),
            "hwp_sha256": hwp_digest,
        }
        print(f"  {slug}: {_tag(unit, '별표제목')[:44]}  "
              f"({len(content):,}자, {digest[:12]})")

    missing = set(targets.values()) - set(part["byeolpyo"])
    if missing:
        raise SystemExit(f"{law_name}: 찾지 못한 별표 {sorted(missing)}")
    return part


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    RAW.mkdir(parents=True, exist_ok=True)

    laws = {name: fetch_law(name, targets) for name, targets in LAWS.items()}

    # 최상위는 도로교통법 시행령 그대로. publish.py 가 이 모양을 읽는다.
    manifest = dict(laws[LEGACY_LAW])
    manifest["laws"] = laws

    (RAW / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n-> {RAW / 'manifest.json'}")


if __name__ == "__main__":
    main()
