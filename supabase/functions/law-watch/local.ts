// index.ts 의 로직을 로컬에서 그대로 돌려 본다.
//
//   node --experimental-strip-types supabase/functions/law-watch/local.ts        # dry-run
//   node --experimental-strip-types supabase/functions/law-watch/local.ts --write # 실제 기록
//
// 배포 전 검증용이다. Edge Function 은 Deno 에서 돌지만 이 파일이 부르는
// runLawWatch 는 웹 표준(fetch, crypto.subtle)만 쓰므로 Node 에서도 같게 동작한다.
// .env 는 프로젝트 루트에서 읽는다.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { runLawWatch, type Env } from "./index.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

function loadEnv(): Record<string, string> {
  const out: Record<string, string> = {};
  let text = "";
  try {
    text = readFileSync(join(root, ".env"), "utf8");
  } catch {
    return out;
  }
  for (const line of text.split(/\r?\n/)) {
    const s = line.trim();
    if (!s || s.startsWith("#") || !s.includes("=")) continue;
    const i = s.indexOf("=");
    out[s.slice(0, i).trim()] = s.slice(i + 1).trim().replace(/^["']|["']$/g, "");
  }
  return out;
}

const file = loadEnv();
const get = (k: string) => process.env[k] ?? file[k] ?? "";

const env: Env = {
  lawApiOc: get("LAW_API_OC") || "test",
  supabaseUrl: get("SUPABASE_URL").replace(/\/$/, ""),
  serviceKey: get("SUPABASE_SERVICE_KEY"),
};

if (!env.supabaseUrl || !env.serviceKey) {
  console.error(".env 에 SUPABASE_URL 과 SUPABASE_SERVICE_KEY 가 필요합니다.");
  process.exit(1);
}

const write = process.argv.includes("--write");
console.log(`OC=${env.lawApiOc}  모드=${write ? "기록" : "dry-run"}`);

const result = await runLawWatch(env, { dry: !write });

console.log(`\n확인한 법령: ${result.checked.join(", ") || "-"}`);
if (result.seeded.length) console.log(`기준선 세움: ${result.seeded.join(", ")}`);
if (result.skipped.length) {
  for (const s of result.skipped) console.log(`  건너뜀: ${s}`);
}
console.log(`\n감지된 변경 ${result.changes.length}건 (시행 예정 ${result.upcoming}건)`);
for (const c of result.changes) {
  console.log(`  [${c.change_type}] ${c.title}`);
  console.log(`      시행 ${c.enforce_date ?? "-"}  ${c.body.slice(0, 90)}`);
}
if (!write) console.log("\n[dry-run] DB 에 아무것도 쓰지 않았습니다.");
