"""검수된 데이터를 Supabase 에 적재한다.

    python pipeline/publish.py --dry-run   # 보낼 내용을 out/publish_preview.json 에만
    python pipeline/publish.py             # 실제 적재

안전장치
  - needs_review 가 하나라도 있으면 적재하지 않는다. 검수가 끝나야 나간다.
  - normalize.build() 를 직접 호출한다. out/violations.json 이 낡아 있어도 상관없고,
    overrides 의 원문 해시 가드도 여기서 같이 걸린다.
  - DB 제약과 같은 검사를 보내기 전에 한 번 더 한다. 실패를 서버까지 끌고 가지 않는다.
  - 별표에서 사라진 행은 지우지 않고 폐지 표시(repealed_at)만 한다.
    지우면 사용자가 저장(즐겨찾기)한 항목이 말없이 없어진다.

적재 순서
    sources upsert
      -> violations upsert
      -> 사라진 violations 에 repealed_at 표시 (되살아난 것은 해제)
      -> 해당 violations 의 penalties 전부 삭제 후 다시 삽입
      -> data_version 증가
penalties 를 지우고 다시 넣는 이유는, upsert 만으로는 이번에 없어진 차종 행이
남기 때문이다.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

import requests

import config
import normalize

RAW = Path(__file__).parent / "raw"
OUT = Path(__file__).parent / "out"
CURATION = Path(__file__).parent / "curation.json"
CURATION_LIVING = Path(__file__).parent / "curation_living.json"
SOURCES = normalize.SLUGS

CHUNK = 200                     # 한 요청에 보낼 행 수
TIMEOUT = 60


# ---------------------------------------------------------------------------
# 행 만들기 (순수 함수 - DB 없이 테스트한다)
# ---------------------------------------------------------------------------

@dataclass
class Payload:
    sources: list[dict] = field(default_factory=list)
    concepts: list[dict] = field(default_factory=list)
    violations: list[dict] = field(default_factory=list)
    penalties: list[dict] = field(default_factory=list)

    @property
    def violation_ids(self) -> list[str]:
        return [v["id"] for v in self.violations]


def zone_of(record: normalize.Record) -> str:
    """보호구역 구분. 별표 7·10 의 목이 곧 구역 구분이다.

    none   일반 도로 (별표 6·8)
    school 어린이보호구역
    senior 노인·장애인보호구역
    both   보호구역이되 어린이/노인 구분 없이 같은 금액
    """
    if record.category != "driving":
        return "none"          # 생활 과태료에는 보호구역이 없다
    if record.source in ("byeolpyo6", "byeolpyo8"):
        return "none"
    if "어린이보호구역" in record.action:
        return "school"
    if "노인" in record.action:
        return "senior"
    return "both"


def _date(yyyymmdd: str) -> str | None:
    """'20260801' -> '2026-08-01'."""
    s = (yyyymmdd or "").strip()
    if len(s) != 8 or not s.isdigit():
        return None
    return f"{s[:4]}-{s[4:6]}-{s[6:]}"


def korean_date(text: str | None) -> str | None:
    """별표 머리말의 '2025. 3. 18.' -> '2025-03-18'. 못 읽으면 None."""
    m = re.match(r"\s*(\d{4})\s*\.\s*(\d{1,2})\s*\.\s*(\d{1,2})", text or "")
    if not m:
        return None
    y, mo, d = (int(g) for g in m.groups())
    return f"{y:04d}-{mo:02d}-{d:02d}"


def build_payload(manifest: dict, byeolpyo_meta: dict,
                  records: list[normalize.Record],
                  curation: dict | None = None) -> Payload:
    """적재할 행을 만든다. 문제가 있으면 SystemExit 으로 멈춘다."""
    curation = curation if curation is not None else load_curation()
    concepts, mapping = curation["concepts"], curation["rows"]

    # 별표마다 소속 법령이 다르다. 시행일도 법령을 따라간다.
    # manifest["laws"] 가 없는 옛 형식이면 최상위를 유일한 법령으로 본다.
    laws = manifest.get("laws") or {manifest["law_name"]: manifest}
    law_of: dict[str, dict] = {}
    for law in laws.values():
        for slug in law["byeolpyo"]:
            law_of[slug] = law

    enforce_of: dict[str, str] = {}
    for slug in byeolpyo_meta:
        law = law_of.get(slug)
        if law is None:
            raise SystemExit(f"{slug}: manifest 에서 소속 법령을 찾지 못했습니다")
        date = _date(law.get("enforce_date", ""))
        if not date:
            raise SystemExit(f"{law['law_name']} 의 enforce_date 를 읽지 못했습니다: "
                             f"{law.get('enforce_date')!r}")
        enforce_of[slug] = date

    payload = Payload()

    for slug, meta in byeolpyo_meta.items():
        law = law_of[slug]
        info = law["byeolpyo"][slug]
        payload.sources.append({
            "slug": slug,
            "law_name": law["law_name"],
            "mst": law["mst"],
            "byeolpyo_label": meta["label"],
            "title": meta["title"],
            "amended": meta["amended"] or None,
            "promulgation_date": _date(law.get("promulgation_date", "")),
            "enforce_date": enforce_of[slug],
            "content_sha256": info["sha256"],
            "hwp_sha256": info.get("hwp_sha256"),
            "notes": meta["notes"],
            "source_url": f"https://www.law.go.kr/LSW/lsInfoP.do?lsiSeq={law['mst']}",
        })

    for key, c in sorted(concepts.items()):
        payload.concepts.append({
            "key": key, "title": c["title"], "summary": c.get("summary"),
            "category": c.get("category", "driving"),
            "subcategory": c.get("subcategory"),
            "awareness_score": c.get("awareness", 0),
            "audience": c.get("audience", "driver"),
        })

    problems: list[str] = []
    seen_keys: set[tuple] = set()
    used_concepts: set[str] = set()

    for r in records:
        if r.needs_review:
            problems.append(f"{r.ref}: 검수가 끝나지 않았습니다 - {r.review_note}")
            continue
        if not r.penalties:
            problems.append(f"{r.ref}: 금액이 없습니다")
            continue

        concept = mapping.get(r.id)
        if concept is None:
            problems.append(f"{r.ref}: curation.json 에 개념 매핑이 없습니다 ({r.id})")
            continue
        if concept not in concepts:
            problems.append(f"{r.ref}: 정의되지 않은 개념 {concept!r}")
            continue
        used_concepts.add(concept)

        payload.violations.append({
            "id": r.id,
            "source_slug": r.source,
            "concept": concept,
            "zone": zone_of(r),
            "category": r.category,
            "ref": r.ref,
            "item_no": r.item_no,
            "sub_no": r.sub_no,
            "action": r.action,
            "parent_action": r.parent_action,
            "legal_basis": r.basis,
            "penalty_formula": r.penalty_formula,
            "confirmed_by": r.confirmed_by,
            "needs_review": False,
        })

        effective = enforce_of[r.source]
        for p in r.penalties:
            key = (r.id, r.kind, p.vehicle, p.offense_count, effective)
            if key in seen_keys:
                problems.append(
                    f"{r.ref}: 차종 {p.vehicle} {p.offense_count}차가 중복됩니다")
                continue
            seen_keys.add(key)
            if p.surcharge_krw is not None and p.surcharge_krw < p.amount_krw:
                problems.append(
                    f"{r.ref}: 가중 금액({p.surcharge_krw})이 기본 금액({p.amount_krw})보다 작습니다")
            payload.penalties.append({
                "violation_id": r.id,
                "kind": r.kind,
                "vehicle_type": p.vehicle,
                "offense_count": p.offense_count,
                "amount_krw": p.amount_krw,
                "surcharge_krw": p.surcharge_krw,
                "effective_from": effective,
                "effective_to": None,
            })

    unused = sorted(set(concepts) - used_concepts)
    if unused:
        problems.append(f"쓰이지 않는 개념이 있습니다: {unused}")

    # 같은 칸(개념·종류·구역·차종)에 금액이 둘 이상이면
    # 카드에 무엇을 보여줄지 정할 수 없다. 개념을 나눠야 한다.
    concept_of = {v["id"]: (v["concept"], v["zone"]) for v in payload.violations}
    cell: dict[tuple, set] = {}
    for p in payload.penalties:
        concept, zone = concept_of[p["violation_id"]]
        key = (concept, p["kind"], zone, p["vehicle_type"], p["offense_count"])
        cell.setdefault(key, set()).add((p["amount_krw"], p["surcharge_krw"]))
    for key, amounts in sorted(cell.items(), key=lambda kv: str(kv[0])):
        if len(amounts) > 1:
            problems.append(
                f"개념 {key[0]} / {key[1]} / {key[2]} / {key[3]} / {key[4]}차 에 "
                f"금액이 둘 이상입니다: {sorted(amounts)}. 개념을 나누세요.")

    if problems:
        raise SystemExit(
            "적재를 중단합니다. 아래를 해결한 뒤 다시 실행하세요.\n  - "
            + "\n  - ".join(problems))

    return payload


def plan_repeals(rows: list[dict],
                 published: set[str]) -> tuple[dict[str, list[str]], list[str]]:
    """DB 에 있는 행과 이번에 실을 행을 견줘 무엇을 폐지 표시할지 정한다.

    지우지 않는 이유는 사용자가 저장(즐겨찾기)한 항목이 사라지지 않게 하기 위해서다.
    개정으로 되살아난 행은 폐지 표시를 해제한다.

    반환: ({출처 슬러그: [폐지할 id]}, [되살릴 id])
    """
    by_source: dict[str, list[str]] = {}
    revive: list[str] = []
    for r in rows:
        if r["id"] not in published:
            if r["repealed_at"] is None:
                by_source.setdefault(r["source_slug"], []).append(r["id"])
        elif r["repealed_at"] is not None:
            revive.append(r["id"])
    return by_source, revive


def load_curation() -> dict:
    """도로교통법과 생활 과태료 큐레이션을 합친다.

    생활 쪽 rows 는 별표 참조('가목 1) 가)')를 열쇠로 쓴다. 사람이 CSV 와
    대조하며 쓰는 파일이라 그 편이 읽힌다. 여기서 레코드 id 로 바꾼다.
    concepts 에는 갈래를 박아 둔다 — 파일이 곧 갈래이므로 손으로 적지 않는다.
    """
    data = json.loads(CURATION.read_text(encoding="utf-8"))
    concepts = {k: {**v, "category": v.get("category", "driving")}
                for k, v in data["concepts"].items()}
    rows = dict(data["rows"])

    if CURATION_LIVING.exists():
        living = json.loads(CURATION_LIVING.read_text(encoding="utf-8"))
        clash = set(living["concepts"]) & set(concepts)
        if clash:
            raise SystemExit(f"개념 키가 겹칩니다: {sorted(clash)}")
        concepts |= {k: {**v, "category": "waste"}
                     for k, v in living["concepts"].items()}
        for ref, key in living["rows"].items():
            rows[normalize.row_id("waste8", ref)] = key
    return {"concepts": concepts, "rows": rows}


def collect() -> tuple[dict, Payload]:
    manifest = json.loads((RAW / "manifest.json").read_text(encoding="utf-8"))
    meta: dict = {}
    records: list[normalize.Record] = []
    for slug in SOURCES:
        recs, b = normalize.build(slug, RAW)
        meta[slug] = {"label": b.label, "title": b.title,
                      "amended": b.amended, "notes": b.notes}
        records += recs
    return manifest, build_payload(manifest, meta, records)


# ---------------------------------------------------------------------------
# Supabase (PostgREST)
# ---------------------------------------------------------------------------

class Supabase:
    def __init__(self, url: str, key: str) -> None:
        self.base = url.rstrip("/") + "/rest/v1"
        self.session = requests.Session()
        self.session.headers.update({
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        })

    def _check(self, res: requests.Response, what: str) -> requests.Response:
        if res.status_code >= 400:
            raise SystemExit(f"{what} 실패 (HTTP {res.status_code})\n  {res.text[:500]}")
        return res

    def upsert(self, table: str, rows: list[dict], on_conflict: str) -> None:
        for i in range(0, len(rows), CHUNK):
            self._check(self.session.post(
                f"{self.base}/{table}", params={"on_conflict": on_conflict},
                headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
                json=rows[i:i + CHUNK], timeout=TIMEOUT), f"{table} upsert")

    def insert(self, table: str, rows: list[dict]) -> None:
        for i in range(0, len(rows), CHUNK):
            self._check(self.session.post(
                f"{self.base}/{table}", headers={"Prefer": "return=minimal"},
                json=rows[i:i + CHUNK], timeout=TIMEOUT), f"{table} insert")

    def select(self, table: str, columns: str, where: dict) -> list[dict]:
        params = {"select": columns, **where}
        res = self._check(self.session.get(f"{self.base}/{table}", params=params,
                                           timeout=TIMEOUT), f"{table} select")
        return res.json()

    def patch_in(self, table: str, column: str, values: list[str], data: dict) -> None:
        for i in range(0, len(values), CHUNK):
            quoted = ",".join('"' + v.replace('"', '\\"') + '"'
                              for v in values[i:i + CHUNK])
            self._check(self.session.patch(
                f"{self.base}/{table}", params={column: f"in.({quoted})"},
                headers={"Prefer": "return=minimal"}, json=data, timeout=TIMEOUT),
                f"{table} patch")

    def delete_in(self, table: str, column: str, values: list[str]) -> int:
        for i in range(0, len(values), CHUNK):
            chunk = values[i:i + CHUNK]
            quoted = ",".join('"' + v.replace('"', '\\"') + '"' for v in chunk)
            self._check(self.session.delete(
                f"{self.base}/{table}", params={column: f"in.({quoted})"},
                headers={"Prefer": "return=minimal"}, timeout=TIMEOUT),
                f"{table} delete")
        return len(values)

    def bump_data_version(self) -> int:
        res = self._check(self.session.get(
            f"{self.base}/data_version", params={"select": "version", "id": "eq.1"},
            timeout=TIMEOUT), "data_version 조회")
        rows = res.json()
        if not rows:
            raise SystemExit("data_version 행이 없습니다. 마이그레이션을 먼저 적용하세요.")
        version = int(rows[0]["version"]) + 1
        self._check(self.session.patch(
            f"{self.base}/data_version", params={"id": "eq.1"},
            headers={"Prefer": "return=minimal"},
            json={"version": version, "updated_at": "now()"}, timeout=TIMEOUT),
            "data_version 갱신")
        return version


def push(client: Supabase, payload: Payload) -> dict:
    client.upsert("sources", payload.sources, "slug")
    client.upsert("concepts", payload.concepts, "key")
    client.upsert("violations", payload.violations, "id")

    # 별표에서 사라진 행은 지우지 않고 폐지 표시만 한다.
    # 지우면 사용자가 저장(즐겨찾기)한 항목이 말없이 없어진다.
    slugs = ",".join(f'"{s["slug"]}"' for s in payload.sources)
    rows = client.select("violations", "id,source_slug,repealed_at",
                         {"source_slug": f"in.({slugs})"})
    published = set(payload.violation_ids)
    repeal_info = {s["slug"]: (s["amended"], s["byeolpyo_label"]) for s in payload.sources}

    by_source, revive = plan_repeals(rows, published)

    repealed: list[str] = []
    for slug, ids in sorted(by_source.items()):
        amended, label = repeal_info.get(slug, (None, slug))
        client.patch_in("violations", "id", sorted(ids), {
            "repealed_at": korean_date(amended) or _date(
                str(payload.sources[0]["enforce_date"]).replace("-", "")),
            "repealed_reason": f"{label} <개정 {amended}> 에서 확인되지 않음"
                               if amended else f"{label} 현행본에서 확인되지 않음",
        })
        repealed += sorted(ids)

    if revive:
        client.patch_in("violations", "id", sorted(revive),
                        {"repealed_at": None, "repealed_reason": None})

    # 폐지된 행의 금액은 남겨 둔다 (그때는 얼마였는지 보여주기 위해).
    # 이번에 실린 행만 지우고 다시 넣는다.
    client.delete_in("violation_penalties", "violation_id", payload.violation_ids)
    client.insert("violation_penalties", payload.penalties)

    version = client.bump_data_version()
    return {"repealed": repealed, "revived": sorted(revive), "data_version": version}


# ---------------------------------------------------------------------------

def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="검수된 과태료 데이터를 Supabase 에 적재")
    ap.add_argument("--dry-run", action="store_true",
                    help="보낼 내용만 out/publish_preview.json 에 쓰고 끝낸다")
    args = ap.parse_args()

    manifest, payload = collect()
    OUT.mkdir(parents=True, exist_ok=True)

    for src in payload.sources:
        print(f"{src['law_name']} {src['byeolpyo_label']} "
              f"MST={src['mst']} 시행={src['enforce_date']}")
    print(f"  출처 {len(payload.sources)}건 / 개념 {len(payload.concepts)}건 / "
          f"위반행위 {len(payload.violations)}건 / 금액 {len(payload.penalties)}건")

    if args.dry_run:
        path = OUT / "publish_preview.json"
        path.write_text(json.dumps(asdict(payload), ensure_ascii=False, indent=2),
                        encoding="utf-8")
        print(f"\n[dry-run] 보내지 않았습니다 -> {path}")
        return

    url = config.require("SUPABASE_URL", "예: https://xxxx.supabase.co")
    key = config.require("SUPABASE_SERVICE_KEY",
                         "프로젝트 설정 > API > service_role. 앱에는 절대 넣지 말 것.")
    result = push(Supabase(url, key), payload)

    if result["repealed"]:
        print(f"  폐지 표시 {len(result['repealed'])}건 (지우지 않습니다): "
              f"{', '.join(result['repealed'][:5])}"
              + (" ..." if len(result["repealed"]) > 5 else ""))
    if result["revived"]:
        print(f"  폐지 해제 {len(result['revived'])}건: {', '.join(result['revived'][:5])}")
    print(f"\n적재 완료. data_version = {result['data_version']}")


if __name__ == "__main__":
    main()
