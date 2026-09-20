"""앱에 번들할 seed JSON 을 만든다.

    python pipeline/export_seed.py

앱은 오프라인 우선이다. 최초 실행 때 네트워크가 없어도 전체 데이터가 보여야
하므로 이 파일을 앱에 함께 넣는다. 이후에는 data_version 이 올라갔을 때만
Supabase 에서 내려받아 갱신한다.

publish.py 와 같은 build_payload() 를 쓴다. 앱이 보는 데이터와 DB 에 올라간
데이터가 어긋날 수 없게 하려는 것이다.

앱이 쓰기 좋게 모양만 바꾼다.
  - penalties 를 violation 안에 넣는다 (앱에서 조인할 일이 없게)
  - 키 이름을 짧게 (번들 크기)
  - 폐지된 행은 seed 에 없다. 갱신 때 서버에서 받아 온다.
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import publish

APP = Path(__file__).parent.parent / "app"
OUT = APP / "assets" / "seed.json"
ENV_OUT = APP / "env.json"     # gitignore 된다


def build() -> dict:
    manifest, payload = publish.collect()

    by_violation: dict[str, list[dict]] = defaultdict(list)
    for p in payload.penalties:
        by_violation[p["violation_id"]].append({
            "kind": p["kind"],
            "veh": p["vehicle_type"],
            "amt": p["amount_krw"],
            # 1차는 기본값이라 싣지 않는다. seed 가 커지지 않게.
            **({"n": p["offense_count"]} if p["offense_count"] != 1 else {}),
            **({"sur": p["surcharge_krw"]} if p["surcharge_krw"] else {}),
        })

    violations = []
    for v in payload.violations:
        violations.append({
            "id": v["id"],
            "concept": v["concept"],
            "cat": v["category"],
            "zone": v["zone"],
            "source": v["source_slug"],
            "ref": v["ref"],
            "action": v["action"],
            **({"parent": v["parent_action"]} if v["parent_action"] else {}),
            "basis": v["legal_basis"],
            **({"formula": v["penalty_formula"]} if v["penalty_formula"] else {}),
            **({"confirmed": v["confirmed_by"]} if v["confirmed_by"] else {}),
            "penalties": sorted(by_violation[v["id"]],
                                key=lambda p: (p["kind"], p.get("n", 1), p["veh"])),
        })

    return {
        "version": 0,          # 번들 seed 는 0. 서버에서 받으면 실제 data_version 이 된다
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        # 법령이 둘 이상이다. 최상위 law 는 도로교통법을 가리키는 옛 필드로,
        # 앱이 출처마다 law/enforce 를 읽도록 바뀐 뒤에도 당분간 남겨 둔다.
        "law": {
            "name": manifest["law_name"],
            "mst": manifest["mst"],
            "enforce_date": publish._date(manifest["enforce_date"]),
        },
        "sources": [{
            "slug": s["slug"],
            "label": s["byeolpyo_label"],
            "title": s["title"],
            "amended": s["amended"],
            "notes": s["notes"],
            "url": s["source_url"],
            "law": s["law_name"],
            "enforce": s["enforce_date"],
        } for s in payload.sources],
        "concepts": [{
            "key": c["key"],
            "title": c["title"],
            "summary": c["summary"],
            "sub": c["subcategory"],
            "score": c["awareness_score"],
            "audience": c["audience"],
            "cat": c["category"],
        } for c in sorted(payload.concepts, key=lambda c: (-c["awareness_score"], c["key"]))],
        "violations": violations,
    }


# 앱에 넘길 값. 모두 앱에 그대로 들어가는 공개 값이다.
# 서비스 키나 서비스 계정은 여기 절대 넣지 않는다.
ENV_KEYS = (
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "FIREBASE_API_KEY",
    "FIREBASE_APP_ID",
    "FIREBASE_SENDER_ID",
    "FIREBASE_PROJECT_ID",
)


def write_env() -> None:
    """앱 빌드 인자. flutter run --dart-define-from-file=env.json

    anon 키와 Firebase 설정값은 앱에 그대로 들어가는 공개 값이라 비밀이
    아니지만, 저장소에 두면 교체가 번거로워지므로 빌드 때 넘긴다.

    빠진 값은 그냥 빼고 쓴다. Supabase 가 없으면 앱이 seed 만으로,
    Firebase 가 없으면 푸시만 빼고 동작한다.
    """
    import config
    values = {k: v for k in ENV_KEYS if (v := config.get(k))}
    if not {"SUPABASE_URL", "SUPABASE_ANON_KEY"} <= values.keys():
        print("  (SUPABASE_URL / SUPABASE_ANON_KEY 가 없어 env.json 은 건너뜁니다)")
        return
    ENV_OUT.write_text(json.dumps(values, indent=2), encoding="utf-8")
    missing = [k for k in ENV_KEYS if k not in values]
    note = f"  (없는 값: {', '.join(missing)})" if missing else ""
    print(f"-> {ENV_OUT}{note}")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    seed = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(seed, ensure_ascii=False, separators=(",", ":")),
                   encoding="utf-8")
    size = OUT.stat().st_size
    print(f"개념 {len(seed['concepts'])} / 위반행위 {len(seed['violations'])} / "
          f"금액 {sum(len(v['penalties']) for v in seed['violations'])}")
    print(f"-> {OUT}  ({size / 1024:.0f} KB)")
    write_env()


if __name__ == "__main__":
    main()
