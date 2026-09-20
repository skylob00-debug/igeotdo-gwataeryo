// 법령 변경 알림 발송 (Supabase Edge Function)
//
// law-watch 가 감지해 쌓아 둔 law_changes 중에서
//   published = true  이고  push = true  이고  notified_at is null
// 인 것만 FCM 으로 내보내고 notified_at 을 찍는다.
//
// published 와 push 를 가른 이유는 0006_push_flag.sql 에 적었다. 줄이면,
// 앱 알림 목록에는 올릴 값이 있지만 폰을 울릴 값은 아닌 건이 있다
// (예: 이 앱이 다루지 않는 벌점 개정).
//
// 감지와 발송을 갈라 둔 이유는 law-watch 주석에 적은 그대로다. 법령 API 는
// 자잘한 타법개정까지 잡아내므로, 사람이 문구를 다듬고 published=true 로
// 바꾼 것만 알림이 된다. 이 함수를 매일 돌려도 사람이 열지 않은 것은 안 나간다.
//
// 보내는 방식은 토픽(law-changes) 하나다. 기기 토큰을 하나씩 도는 방식은
// 지금 규모에 이르지도 않았고, 만료 토큰 청소라는 일거리만 늘린다.
// 대상을 갈라야 할 때(예: 지역별)가 오면 devices.topics 를 쓰면 된다.
//
// FCM HTTP v1 은 서비스 계정으로 서명한 JWT 를 access token 으로 바꿔 쓴다.
// 레거시 서버 키(AAAA...)는 2024 년에 끝났다.
//
// 로직은 웹 표준(fetch, crypto.subtle)만 쓴다. Deno 전용 코드는 맨 아래
// 진입점뿐이라 Node 로도 그대로 실행해 검증할 수 있다.
//   node --experimental-strip-types supabase/functions/push-notify/local.ts

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOPIC = "law-changes";

/** 알림 본문 길이. 잠금화면에서 잘리는 것을 앱이 먼저 자른다. */
const BODY_MAX = 120;

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

export interface Env {
  supabaseUrl: string;
  serviceKey: string;
  serviceAccount: ServiceAccount;
}

export interface Change {
  id: number;
  law_name: string;
  change_type: "amended" | "upcoming" | "byeolpyo_changed";
  enforce_date: string | null;
  title: string;
  body: string;
}

export interface Sent {
  id: number;
  title: string;
  body: string;
  message_id: string | null;
  error: string | null;
}

export interface Result {
  dry: boolean;
  topic: string;
  pending: number;
  sent: Sent[];
  failed: number;
}

// --- Supabase -------------------------------------------------------------

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

  async patch(path: string, body: unknown) {
    await this.call("PATCH", path, {
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify(body),
    });
  }
}

// --- 서비스 계정 -> access token -----------------------------------------

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlText(text: string): string {
  return b64url(new TextEncoder().encode(text));
}

/** PEM(PKCS#8) 을 서명용 키로 읽는다. */
async function importKey(pem: string): Promise<CryptoKey> {
  // Supabase 시크릿에 넣으면 줄바꿈이 \n 두 글자로 들어오는 경우가 많다.
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----[A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

export async function accessToken(sa: ServiceAccount): Promise<string> {
  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64urlText(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.` +
    b64urlText(JSON.stringify(claim));

  const key = await importKey(sa.private_key);
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;

  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`토큰 발급 실패 HTTP ${res.status}: ${text.slice(0, 300)}`);
  const token = JSON.parse(text).access_token as string | undefined;
  if (!token) throw new Error(`토큰 발급 응답에 access_token 이 없습니다: ${text.slice(0, 200)}`);
  return token;
}

// --- 문구 -----------------------------------------------------------------

/** 알림에 띄울 한 줄. 잘릴 때는 문장 중간이 아니라 말줄임으로. */
export function shorten(text: string, max = BODY_MAX): string {
  const one = text.replace(/\s+/g, " ").trim();
  return one.length <= max ? one : `${one.slice(0, max - 1)}…`;
}

/** 본문이 비었을 때 쓸 기본 문구. 종류마다 사용자가 할 일이 다르다. */
function fallbackBody(c: Change): string {
  switch (c.change_type) {
    case "upcoming":
      return c.enforce_date
        ? `${c.enforce_date}부터 달라집니다. 앱에서 확인하세요.`
        : "시행 예정 내용이 있습니다. 앱에서 확인하세요.";
    case "byeolpyo_changed":
      return "과태료·범칙금 금액이 바뀌었습니다. 앱에서 확인하세요.";
    default:
      return `${c.law_name}이(가) 개정됐습니다. 앱에서 확인하세요.`;
  }
}

export function buildMessage(c: Change, topic: string) {
  const title = shorten(c.title, 60);
  const body = shorten(c.body || fallbackBody(c));
  return {
    message: {
      topic,
      notification: { title, body },
      // 앱이 켜져 있을 때는 notification 이 화면에 뜨지 않는다.
      // 그때 쓰려고 같은 내용을 data 에도 싣는다. data 값은 문자열만 된다.
      data: {
        change_id: String(c.id),
        change_type: c.change_type,
        law_name: c.law_name,
        enforce_date: c.enforce_date ?? "",
        title,
        body,
      },
      android: {
        priority: "NORMAL",
        notification: { channel_id: "law_changes", default_sound: true },
      },
      apns: {
        headers: { "apns-priority": "5" },
        payload: { aps: { sound: "default" } },
      },
    },
  };
}

// --- 본체 -----------------------------------------------------------------

export async function runPushNotify(
  env: Env,
  opts: { dry?: boolean; id?: number; force?: boolean } = {},
): Promise<Result> {
  const dry = opts.dry ?? false;
  const db = new Db(env);

  const cols = "id,law_name,change_type,enforce_date,title,body";
  let query =
    `law_changes?select=${cols}&published=is.true&push=is.true&order=id.asc`;
  // force 는 이미 보낸 것을 다시 보낸다. 특정 건을 집어 줄 때만 허용한다.
  if (!(opts.force && opts.id)) query += "&notified_at=is.null";
  if (opts.id) query += `&id=eq.${opts.id}`;

  const pending = await db.select<Change>(query);
  const result: Result = { dry, topic: TOPIC, pending: pending.length, sent: [], failed: 0 };
  if (!pending.length) return result;

  const token = dry ? "" : await accessToken(env.serviceAccount);
  const url =
    `https://fcm.googleapis.com/v1/projects/${env.serviceAccount.project_id}/messages:send`;

  for (const c of pending) {
    const payload = buildMessage(c, TOPIC);
    const row: Sent = {
      id: c.id,
      title: payload.message.notification.title,
      body: payload.message.notification.body,
      message_id: null,
      error: null,
    };

    if (dry) {
      result.sent.push(row);
      continue;
    }

    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const text = await res.text();
      if (!res.ok) throw new Error(`FCM HTTP ${res.status}: ${text.slice(0, 300)}`);
      row.message_id = (JSON.parse(text).name as string | undefined) ?? null;

      // 보낸 뒤에만 찍는다. 실패한 건은 다음 실행에서 다시 집힌다.
      await db.patch(`law_changes?id=eq.${c.id}`, {
        notified_at: new Date().toISOString(),
      });
    } catch (err) {
      row.error = String(err instanceof Error ? err.message : err);
      result.failed += 1;
    }
    result.sent.push(row);
  }

  return result;
}

// --- Deno 진입점 (Supabase Edge Functions) --------------------------------
// Node 로 로직을 검증할 때는 Deno 가 없으므로 이 블록을 건너뛴다.

declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Promise<Response>): void;
} | undefined;

export function parseServiceAccount(raw: string): ServiceAccount {
  const sa = JSON.parse(raw) as Partial<ServiceAccount>;
  for (const k of ["project_id", "client_email", "private_key"] as const) {
    if (!sa[k]) throw new Error(`FIREBASE_SERVICE_ACCOUNT 에 ${k} 가 없습니다`);
  }
  return sa as ServiceAccount;
}

if (typeof Deno !== "undefined") {
  Deno.serve(async (req: Request) => {
    // law-watch 와 같은 방식이다. 게이트웨이의 JWT 검증은 꺼 두고
    // 여기서 직접 본다. CRON_SECRET 이든 서비스 키든 맞으면 통과.
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

    const params = new URL(req.url).searchParams;
    const dry = params.get("dry") === "1";
    const idParam = params.get("id");

    try {
      const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";
      // dry-run 은 서비스 계정 없이도 무엇이 나갈지 볼 수 있어야 한다.
      const serviceAccount = raw
        ? parseServiceAccount(raw)
        : dry
        ? { project_id: "(미설정)", client_email: "", private_key: "" }
        : (() => {
          throw new Error("FIREBASE_SERVICE_ACCOUNT 시크릿이 없습니다");
        })();

      const env: Env = {
        supabaseUrl: (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, ""),
        serviceKey: serviceKey || auth,
        serviceAccount,
      };
      const result = await runPushNotify(env, {
        dry,
        id: idParam ? Number(idParam) : undefined,
        force: params.get("force") === "1",
      });
      return new Response(JSON.stringify(result, null, 2), {
        status: result.failed ? 502 : 200,
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
