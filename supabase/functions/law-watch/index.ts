// 법령 개정 감지 (Supabase Edge Function)
//
// 매일 한 번 돌면서 세 가지를 본다.
//   1. 시행 중인 법령의 법령일련번호(MST)·시행일자가 바뀌었는가   -> 'amended'
//   2. 감시 대상 별표의 내용 해시가 바뀌었는가                    -> 'byeolpyo_changed'
//   3. 앞으로 시행될 도로교통법 계열 법령이 있는가                 -> 'upcoming'
//
// 감지만 하고 알림은 보내지 않는다. law_changes 에 published=false 로 쌓이고,
// 사람이 문구를 다듬어 published=true 로 바꿔야 앱과 푸시에 나간다.
// 법령 API 는 자잘한 타법개정까지 잡아내므로 그대로 쏘면 알림 스팸이 된다.
//
// 로직은 웹 표준(fetch, crypto.subtle)만 쓴다. Deno 전용 코드는 맨 아래
// 진입점뿐이라 Node 로도 그대로 실행해 검증할 수 있다.
//   node --experimental-strip-types supabase/functions/law-watch/local.ts

const LAW_API = "https://www.law.go.kr/DRF";
const UA = "gwataeryo-alrimi/0.1";

export interface Env {
  lawApiOc: string;
  supabaseUrl: string;
  serviceKey: string;
}

interface Target {
  lawName: string;
  byeolpyo: string[]; // 별표번호 4자리. 빈 배열이면 별표는 보지 않는다
}

/** 감시 대상. 별표는 pipeline/fetch_byeolpyo.py 의 TARGETS 와 맞춰 둔다. */
export const TARGETS: Target[] = [
  { lawName: "도로교통법", byeolpyo: [] },
  { lawName: "도로교통법 시행령", byeolpyo: ["0006", "0007", "0008", "0010"] },
  { lawName: "도로교통법 시행규칙", byeolpyo: [] },
];

/** 시행 예정 법령을 훑을 때 쓰는 검색어와 이름 접두사 */
const UPCOMING_QUERY = "도로교통법";

export interface Change {
  law_id: string;
  law_name: string;
  change_type: "amended" | "upcoming" | "byeolpyo_changed";
  promulgation_date: string | null;
  enforce_date: string | null;
  title: string;
  body: string;
  source_url: string | null;
}

export interface Result {
  dry: boolean;
  checked: string[];
  seeded: string[];
  changes: Change[];
  upcoming: number;
  skipped: string[];
}

// --- 법령 API -------------------------------------------------------------

function isoDate(yyyymmdd: string | null): string | null {
  if (!yyyymmdd || !/^\d{8}$/.test(yyyymmdd)) return null;
  return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6)}`;
}

function tag(block: string, name: string): string | null {
  const m = block.match(new RegExp(`<${name}>(.*?)</${name}>`, "s"));
  if (!m) return null;
  return m[1].replace(/<!\[CDATA\[|\]\]>/g, "").trim();
}

async function fetchXml(path: string, params: Record<string, string>): Promise<string> {
  const qs = new URLSearchParams(params).toString();
  const res = await fetch(`${LAW_API}/${path}?${qs}`, {
    headers: { "User-Agent": UA, Referer: "https://www.law.go.kr/" },
  });
  if (!res.ok) throw new Error(`법령 API ${path} HTTP ${res.status}`);
  const text = await res.text();
  const code = text.match(/<resultCode>(\d+)<\/resultCode>/);
  if (code && code[1] !== "00") {
    throw new Error(`법령 API 오류 코드 ${code[1]}: ${text.slice(0, 200)}`);
  }
  return text;
}

export interface LawRow {
  name: string;
  mst: string;
  promulgation: string | null;
  enforce: string | null;
}

/** target=law / target=eflaw 응답을 항목 목록으로. 둘 다 <law> 태그를 쓴다. */
export function parseLawList(xml: string): LawRow[] {
  const out: LawRow[] = [];
  for (const m of xml.matchAll(/<law\s+id="\d+">(.*?)<\/law>/gs)) {
    const name = tag(m[1], "법령명한글");
    const mst = tag(m[1], "법령일련번호");
    if (!name || !mst) continue;
    out.push({
      name,
      mst,
      promulgation: tag(m[1], "공포일자"),
      enforce: tag(m[1], "시행일자"),
    });
  }
  return out;
}

/** 법령 본문에서 별표번호 -> 별표내용. 가지번호가 00 인 것만 본다. */
export function parseByeolpyo(xml: string): Map<string, string> {
  const out = new Map<string, string>();
  for (const m of xml.matchAll(/<별표단위[^>]*>(.*?)<\/별표단위>/gs)) {
    const no = tag(m[1], "별표번호");
    const branch = tag(m[1], "별표가지번호");
    const content = tag(m[1], "별표내용");
    if (no && branch === "00" && content) out.set(no, content);
  }
  return out;
}

export async function sha256(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// --- Supabase (PostgREST) -------------------------------------------------

class Db {
  env: Env;

  constructor(env: Env) {
    this.env = env;
  }

  async call(method: string, path: string, init: RequestInit = {}) {
    const res = await fetch(`${this.env.supabaseUrl}/rest/v1/${path}`, {
      ...init,
      method,
      headers: {
        apikey: this.env.serviceKey,
        Authorization: `Bearer ${this.env.serviceKey}`,
        "Content-Type": "application/json",
        ...(init.headers ?? {}),
      },
    });
    if (!res.ok) {
      throw new Error(`${method} ${path} HTTP ${res.status}: ${(await res.text()).slice(0, 300)}`);
    }
    return res;
  }

  async select<T>(path: string): Promise<T[]> {
    return await (await this.call("GET", path)).json();
  }

  async upsert(table: string, rows: unknown[], onConflict: string) {
    if (!rows.length) return;
    await this.call("POST", `${table}?on_conflict=${onConflict}`, {
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify(rows),
    });
  }

  async insert(table: string, rows: unknown[]) {
    if (!rows.length) return;
    await this.call("POST", table, {
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify(rows),
    });
  }
}

interface WatchRow {
  law_id: string;
  last_mst: string | null;
  last_enforce_date: string | null;
  last_byeolpyo_hash: Record<string, string>;
}

// --- 본체 -----------------------------------------------------------------

export async function runLawWatch(env: Env, opts: { dry?: boolean } = {}): Promise<Result> {
  const dry = opts.dry ?? false;
  const db = new Db(env);
  const oc = env.lawApiOc;

  const watched = await db.select<WatchRow>(
    "law_watch?select=law_id,last_mst,last_enforce_date,last_byeolpyo_hash",
  );
  const known = new Map(watched.map((w) => [w.law_id, w]));

  const result: Result = {
    dry, checked: [], seeded: [], changes: [], upcoming: 0, skipped: [],
  };
  const watchRows: unknown[] = [];

  for (const target of TARGETS) {
    const list = parseLawList(
      await fetchXml("lawSearch.do", {
        OC: oc, target: "law", query: target.lawName, type: "XML", display: "20",
      }),
    );
    const cur = list.find((r) => r.name === target.lawName);
    if (!cur) {
      result.skipped.push(`${target.lawName}: 목록에서 찾지 못했습니다`);
      continue;
    }
    result.checked.push(target.lawName);

    // 별표 해시는 감시 대상이 있을 때만 본문을 받는다 (호출을 아낀다)
    let hashes: Record<string, string> = {};
    if (target.byeolpyo.length) {
      const body = await fetchXml("lawService.do", {
        OC: oc, target: "law", MST: cur.mst, type: "XML",
      });
      const contents = parseByeolpyo(body);
      for (const no of target.byeolpyo) {
        const text = contents.get(no);
        if (text) hashes[no] = await sha256(text);
        else result.skipped.push(`${target.lawName} 별표 ${no}: 본문에서 찾지 못했습니다`);
      }
    }

    const prev = known.get(target.lawName);
    const enforceIso = isoDate(cur.enforce);
    const sourceUrl = `https://www.law.go.kr/LSW/lsInfoP.do?lsiSeq=${cur.mst}`;

    if (!prev) {
      // 첫 실행은 기준선만 세운다. 없던 변화를 만들어 내지 않는다.
      result.seeded.push(target.lawName);
    } else {
      if (prev.last_mst !== cur.mst || prev.last_enforce_date !== enforceIso) {
        result.changes.push({
          law_id: target.lawName,
          law_name: target.lawName,
          change_type: "amended",
          promulgation_date: isoDate(cur.promulgation),
          enforce_date: enforceIso,
          title: `${target.lawName} 개정`,
          body:
            `법령일련번호 ${prev.last_mst ?? "-"} -> ${cur.mst}, ` +
            `시행일 ${prev.last_enforce_date ?? "-"} -> ${enforceIso ?? "-"}`,
          source_url: sourceUrl,
        });
      }
      for (const [no, hash] of Object.entries(hashes)) {
        const before = prev.last_byeolpyo_hash?.[no];
        if (before && before !== hash) {
          result.changes.push({
            law_id: target.lawName,
            law_name: target.lawName,
            change_type: "byeolpyo_changed",
            promulgation_date: isoDate(cur.promulgation),
            enforce_date: enforceIso,
            title: `${target.lawName} 별표 ${Number(no)} 변경`,
            // 금액이 바뀌었을 수 있다. 파이프라인을 다시 돌려 검수해야 한다.
            body:
              `별표 ${Number(no)} 내용 해시가 달라졌습니다. ` +
              `pipeline/fetch_byeolpyo.py 부터 다시 돌리고 검수하세요. ` +
              `${before.slice(0, 12)} -> ${hash.slice(0, 12)}`,
            source_url: sourceUrl,
          });
        }
      }
    }

    watchRows.push({
      law_id: target.lawName,
      law_name: target.lawName,
      last_mst: cur.mst,
      last_enforce_date: enforceIso,
      last_byeolpyo_hash: target.byeolpyo.length ? hashes : (prev?.last_byeolpyo_hash ?? {}),
      last_checked_at: new Date().toISOString(),
    });
  }

  // 시행 예정 법령
  const today = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  const upcoming = parseLawList(
    await fetchXml("lawSearch.do", {
      OC: oc, target: "eflaw", query: UPCOMING_QUERY, type: "XML",
      display: "100", sort: "efdes",
    }),
  ).filter(
    (r) =>
      r.name.startsWith(UPCOMING_QUERY) &&
      r.enforce && r.enforce > today && r.enforce !== "99990101",
  );

  // 이미 기록한 것은 건너뛴다 (매일 돌아도 중복으로 쌓이지 않게)
  const seen = new Set(
    (await db.select<{ law_name: string; enforce_date: string }>(
      "law_changes?select=law_name,enforce_date&change_type=eq.upcoming",
    )).map((r) => `${r.law_name}|${r.enforce_date}`),
  );

  for (const r of upcoming) {
    const enforceIso = isoDate(r.enforce)!;
    if (seen.has(`${r.name}|${enforceIso}`)) continue;
    seen.add(`${r.name}|${enforceIso}`);
    result.upcoming += 1;
    result.changes.push({
      law_id: r.name,
      law_name: r.name,
      change_type: "upcoming",
      promulgation_date: isoDate(r.promulgation),
      enforce_date: enforceIso,
      title: `${enforceIso}부터 ${r.name}이(가) 바뀝니다`,
      body: `시행 예정 법령입니다. 무엇이 달라지는지 확인해 문구를 다듬은 뒤 게시하세요.`,
      source_url: `https://www.law.go.kr/LSW/lsInfoP.do?lsiSeq=${r.mst}`,
    });
  }

  if (!dry) {
    await db.insert(
      "law_changes",
      result.changes.map((c) => ({ ...c, affects_violations: [], published: false })),
    );
    await db.upsert("law_watch", watchRows, "law_id");
  }
  return result;
}

// --- Deno 진입점 (Supabase Edge Functions) --------------------------------
// Node 로 로직을 검증할 때는 Deno 가 없으므로 이 블록을 건너뛴다.

declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Promise<Response>): void;
} | undefined;

if (typeof Deno !== "undefined") {
  Deno.serve(async (req: Request) => {
    // 이 프로젝트는 새 형식 키(sb_secret_...)를 쓰는데 Supabase 가 함수에
    // 주입하는 이름은 구형식 기준이라 다를 수 있다. 쓸 수 있는 것을 모두 받는다.
    // CRON_SECRET 을 따로 두면 어느 쪽이든 확실하게 맞출 수 있다.
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SECRET_KEY") ?? "";
    const accepted = [
      Deno.env.get("CRON_SECRET"),
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
      Deno.env.get("SUPABASE_SECRET_KEY"),
    ].filter((v): v is string => !!v);

    const auth = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!accepted.length || !accepted.includes(auth)) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401, headers: { "Content-Type": "application/json" },
      });
    }
    const env: Env = {
      lawApiOc: Deno.env.get("LAW_API_OC") ?? "test",
      supabaseUrl: (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, ""),
      // DB 접근에는 반드시 service 권한 키를 쓴다 (CRON_SECRET 이 아니라)
      serviceKey: serviceKey || auth,
    };
    const dry = new URL(req.url).searchParams.get("dry") === "1";
    try {
      const result = await runLawWatch(env, { dry });
      return new Response(JSON.stringify(result, null, 2), {
        headers: { "Content-Type": "application/json" },
      });
    } catch (err) {
      return new Response(
        JSON.stringify({ error: String(err instanceof Error ? err.message : err) }, null, 2),
        { status: 500, headers: { "Content-Type": "application/json" } },
      );
    }
  });
}
