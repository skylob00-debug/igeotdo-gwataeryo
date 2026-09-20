// index.ts 의 로직을 로컬에서 그대로 돌려 본다.
//
//   node --experimental-strip-types supabase/functions/push-notify/local.ts          # dry-run
//   node --experimental-strip-types supabase/functions/push-notify/local.ts --send   # 실제 발송
//   node --experimental-strip-types supabase/functions/push-notify/local.ts --send --id 3
//   node --experimental-strip-types supabase/functions/push-notify/local.ts --send --id 3 --force
//
// dry-run 은 서비스 계정 없이도 돈다. 무엇이 나갈지 문구만 보여준다.
// 나가는 것은 published=true 이고 push=true 이고 아직 안 보낸 건뿐이다.
// 실제 발송에는 .env 의 FIREBASE_SERVICE_ACCOUNT_FILE(서비스 계정 JSON 경로)
// 또는 FIREBASE_SERVICE_ACCOUNT(JSON 문자열)가 필요하다.

import { readFileSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";

import { runPushNotify, parseServiceAccount, type Env, type ServiceAccount } from "./index.ts";

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

const send = process.argv.includes("--send");
const force = process.argv.includes("--force");
const idArg = process.argv[process.argv.indexOf("--id") + 1];
const id = process.argv.includes("--id") ? Number(idArg) : undefined;

function serviceAccount(): ServiceAccount {
  const path = get("FIREBASE_SERVICE_ACCOUNT_FILE");
  const raw = path
    ? readFileSync(isAbsolute(path) ? path : join(root, path), "utf8")
    : get("FIREBASE_SERVICE_ACCOUNT");
  if (raw) return parseServiceAccount(raw);
  if (send) {
    console.error(
      ".env 에 FIREBASE_SERVICE_ACCOUNT_FILE 또는 FIREBASE_SERVICE_ACCOUNT 가 필요합니다.",
    );
    process.exit(1);
  }
  return { project_id: "(미설정)", client_email: "", private_key: "" };
}

const env: Env = {
  supabaseUrl: get("SUPABASE_URL").replace(/\/$/, ""),
  serviceKey: get("SUPABASE_SERVICE_KEY"),
  serviceAccount: serviceAccount(),
};

if (!env.supabaseUrl || !env.serviceKey) {
  console.error(".env 에 SUPABASE_URL 과 SUPABASE_SERVICE_KEY 가 필요합니다.");
  process.exit(1);
}

console.log(
  `프로젝트=${env.serviceAccount.project_id}  모드=${send ? "발송" : "dry-run"}` +
    (id ? `  대상=#${id}${force ? " (재발송)" : ""}` : ""),
);

const result = await runPushNotify(env, { dry: !send, id, force });

console.log(`\n보낼 것 ${result.pending}건  토픽=${result.topic}`);
for (const s of result.sent) {
  console.log(`  #${s.id} ${s.title}`);
  console.log(`      ${s.body}`);
  if (s.message_id) console.log(`      -> ${s.message_id}`);
  if (s.error) console.log(`      !! ${s.error}`);
}
if (!send) console.log("\n[dry-run] 아무것도 보내지 않았고 DB 도 건드리지 않았습니다.");
else if (result.failed) {
  console.error(`\n${result.failed}건 실패했습니다. 실패한 건은 다음 실행에서 다시 집힙니다.`);
  process.exit(1);
}
