-- 과태료 알리미 초기 스키마
--
-- 설계 메모
--   1. kind(과태료/범칙금)는 violations 가 아니라 violation_penalties 에 둔다.
--      같은 위반행위가 과태료와 범칙금 양쪽에 걸리기 때문이다.
--   2. surcharge_krw 는 별표 6 비고 4의 가중 금액이다
--      (같은 장소에서 2시간 이상 정차·주차 위반 시 적용). 빠뜨리면 안 된다.
--   3. penalty_formula 는 정수 하나로 표현되지 않는 누진 과태료의 가산 규칙이다.
--      예: "10만원에 3일을 초과할 때마다 10만원을 더한 금액"
--   4. 금액을 보여주는 화면은 sources 의 근거·시행일을 반드시 함께 낸다.
--      이게 이 앱의 법적 리스크 방어선이다.
--
-- 차종 구분은 별표 비고의 정의를 따른다.
--   van        승합자동차등 = 승합차, 4톤 초과 화물차, 특수차, 건설기계, 노면전차
--   car        승용자동차등 = 승용차, 4톤 이하 화물차
--   motorcycle 이륜자동차등 = 이륜차, 원동기장치자전거(개인형 이동장치 제외)
--   bicycle    자전거등 및 손수레등
--   pm         개인형 이동장치
--   all        차종 구분 없음

create extension if not exists pg_trgm;   -- 한글 부분 일치 검색용


-- ---------------------------------------------------------------------------
-- 원문 출처 (별표 단위)
-- 개정 감지의 기준이자 앱 면책 표기의 근거.
-- ---------------------------------------------------------------------------
create table if not exists public.sources (
  slug               text primary key,            -- 'byeolpyo6'
  law_name           text        not null,        -- '도로교통법 시행령'
  mst                text        not null,        -- 법령일련번호
  byeolpyo_label     text        not null,        -- '별표 6'
  title              text        not null,        -- '과태료의 부과기준(...)'
  amended            text,                        -- 별표 머리말의 개정일
  promulgation_date  date,
  enforce_date       date        not null,        -- 이 본문이 효력을 갖는 날
  content_sha256     text        not null,        -- 별표내용(박스아트) 해시
  hwp_sha256         text,                        -- 별표 HWP 원본 해시
  notes              text[]      not null default '{}',   -- 별표 비고
  source_url         text,
  fetched_at         timestamptz not null default now()
);

comment on column public.sources.notes is
  '별표 비고. 차종 정의와 가중 조건이 들어 있어 앱에서 반드시 보여줘야 한다.';


-- ---------------------------------------------------------------------------
-- 위반행위 (부과 단위)
-- ---------------------------------------------------------------------------
create table if not exists public.violations (
  id               text primary key,              -- 'byeolpyo6-4-2-가'
  source_slug      text not null references public.sources(slug) on delete restrict,
  category         text not null default 'driving'
                     check (category in ('driving', 'waste', 'etc')),
  subcategory      text,                          -- '주정차' '속도' '보호구역' 등
  ref              text not null,                 -- '제4의2호 가목'
  item_no          text not null,
  sub_no           text,
  title            text,                          -- 큐레이션. 없으면 앱이 action 을 쓴다
  summary          text,                          -- 큐레이션 한 줄 설명
  action           text not null,                 -- 별표 원문 그대로
  parent_action    text not null default '',      -- 목일 때 상위 항목 본문
  legal_basis      text not null,                 -- '제17조제3항'
  penalty_formula  text not null default '',      -- 누진 가산 규칙 (설계 메모 3)
  awareness_score  int  not null default 0,       -- '몰랐을 가능성' -> 홈 정렬용
  confirmed_by     text not null default '',      -- 사람이 확정한 경우 그 근거
  needs_review     boolean not null default false,
  search_text      text generated always as (
                     coalesce(title, '') || ' ' || coalesce(summary, '') || ' '
                     || action || ' ' || parent_action || ' ' || legal_basis
                   ) stored,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists violations_source_idx
  on public.violations (source_slug);
create index if not exists violations_category_idx
  on public.violations (category, subcategory);
create index if not exists violations_search_idx
  on public.violations using gin (search_text gin_trgm_ops);


-- ---------------------------------------------------------------------------
-- 금액 (차종별, 시행일별)
-- ---------------------------------------------------------------------------
create table if not exists public.violation_penalties (
  violation_id    text    not null references public.violations(id) on delete cascade,
  kind            text    not null check (kind in ('fine', 'ticket')),
  vehicle_type    text    not null
                    check (vehicle_type in ('car', 'van', 'motorcycle', 'bicycle', 'pm', 'all')),
  amount_krw      integer not null check (amount_krw > 0),
  surcharge_krw   integer check (surcharge_krw is null or surcharge_krw >= amount_krw),
  effective_from  date    not null,
  effective_to    date,
  primary key (violation_id, kind, vehicle_type, effective_from),
  constraint penalty_period_valid
    check (effective_to is null or effective_to > effective_from)
);

comment on column public.violation_penalties.surcharge_krw is
  '같은 장소에서 2시간 이상 정차·주차 위반 시 적용되는 가중 금액 (별표 6 비고 4).';

create index if not exists penalties_current_idx
  on public.violation_penalties (violation_id, kind)
  where effective_to is null;


-- ---------------------------------------------------------------------------
-- 법령 개정 감시
-- ---------------------------------------------------------------------------
create table if not exists public.law_watch (
  law_id             text primary key,            -- '도로교통법 시행령'
  law_name           text not null,
  last_mst           text,                        -- 법령일련번호
  last_enforce_date  date,
  last_byeolpyo_hash jsonb not null default '{}', -- {"byeolpyo6": "sha256", ...}
  last_checked_at    timestamptz
);

create table if not exists public.law_changes (
  id                 bigserial primary key,
  law_id             text not null,
  law_name           text not null,
  change_type        text not null
                       check (change_type in ('amended', 'upcoming', 'byeolpyo_changed')),
  promulgation_date  date,
  enforce_date       date,
  title              text not null,
  body               text not null default '',
  source_url         text,
  affects_violations text[] not null default '{}',
  published          boolean not null default false,   -- 검수 후 true 여야 앱에 나간다
  notified_at        timestamptz,                      -- FCM 발송 시각
  created_at         timestamptz not null default now()
);

create index if not exists law_changes_feed_idx
  on public.law_changes (published, enforce_date desc nulls last, created_at desc);

comment on table public.law_changes is
  '감지는 자동, 발송은 수동이다. 법령 API 는 자잘한 타법개정도 잡아내므로 published 를 사람이 true 로 바꿔야 푸시가 나간다.';


-- ---------------------------------------------------------------------------
-- 기기 등록 / 데이터 버전
-- ---------------------------------------------------------------------------
create table if not exists public.devices (
  fcm_token   text primary key,
  platform    text not null check (platform in ('android', 'ios')),
  topics      text[] not null default '{}',
  app_version text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.data_version (
  id         int primary key default 1 check (id = 1),
  version    bigint      not null default 0,
  updated_at timestamptz not null default now()
);

insert into public.data_version (id, version) values (1, 0)
  on conflict (id) do nothing;


-- ---------------------------------------------------------------------------
-- updated_at 자동 갱신
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at() returns trigger
language plpgsql as $fn$
begin
  new.updated_at := now();
  return new;
end;
$fn$;

drop trigger if exists violations_touch on public.violations;
create trigger violations_touch before update on public.violations
  for each row execute function public.touch_updated_at();

drop trigger if exists devices_touch on public.devices;
create trigger devices_touch before update on public.devices
  for each row execute function public.touch_updated_at();


-- ---------------------------------------------------------------------------
-- 기기 등록 함수
-- anon 에게 devices UPDATE 를 열어 주면 남의 등록을 고칠 수 있다.
-- 등록은 이 함수로만 한다.
-- ---------------------------------------------------------------------------
create or replace function public.register_device(
  p_token       text,
  p_platform    text,
  p_topics      text[] default '{}',
  p_app_version text   default null)
returns void
language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.devices (fcm_token, platform, topics, app_version)
  values (p_token, p_platform, coalesce(p_topics, '{}'), p_app_version)
  on conflict (fcm_token) do update
    set platform    = excluded.platform,
        topics      = excluded.topics,
        app_version = excluded.app_version;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- 테이블 권한
--
-- RLS 정책만으로는 접근이 되지 않는다. 정책은 "어떤 행을 볼 수 있는가"를 정할 뿐,
-- 테이블에 접근할 권한 자체는 GRANT 로 따로 줘야 한다. 둘 다 있어야 통과한다.
-- 프로젝트의 기본 권한 설정에 기대지 않고 여기서 명시한다.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;

-- 앱이 읽는 것 (실제로 보이는 행은 아래 RLS 정책이 정한다)
grant select on public.sources             to anon, authenticated;
grant select on public.violations          to anon, authenticated;
grant select on public.violation_penalties to anon, authenticated;
grant select on public.law_changes         to anon, authenticated;
grant select on public.data_version        to anon, authenticated;

-- 적재 스크립트. service_role 은 RLS 를 우회하지만 GRANT 는 따로 필요하다.
grant all on public.sources             to service_role;
grant all on public.violations          to service_role;
grant all on public.violation_penalties to service_role;
grant all on public.law_watch           to service_role;
grant all on public.law_changes         to service_role;
grant all on public.devices             to service_role;
grant all on public.data_version        to service_role;
grant usage, select on all sequences in schema public to service_role;


-- ---------------------------------------------------------------------------
-- RLS
-- 읽기는 anon, 쓰기는 service_role 전용 (적재 스크립트).
-- ---------------------------------------------------------------------------
alter table public.sources             enable row level security;
alter table public.violations          enable row level security;
alter table public.violation_penalties enable row level security;
alter table public.law_changes         enable row level security;
alter table public.law_watch           enable row level security;
alter table public.devices             enable row level security;
alter table public.data_version        enable row level security;

drop policy if exists sources_read on public.sources;
create policy sources_read on public.sources
  for select to anon, authenticated using (true);

-- 검수가 끝나지 않은 행은 앱에 내보내지 않는다.
drop policy if exists violations_read on public.violations;
create policy violations_read on public.violations
  for select to anon, authenticated using (not needs_review);

drop policy if exists penalties_read on public.violation_penalties;
create policy penalties_read on public.violation_penalties
  for select to anon, authenticated using (true);

drop policy if exists law_changes_read on public.law_changes;
create policy law_changes_read on public.law_changes
  for select to anon, authenticated using (published);

drop policy if exists data_version_read on public.data_version;
create policy data_version_read on public.data_version
  for select to anon, authenticated using (true);

-- law_watch 와 devices 는 anon 이 직접 읽거나 쓰지 않는다.
-- 기기 등록은 register_device() 로만 한다.
revoke all on public.devices from anon, authenticated;
grant execute on function public.register_device(text, text, text[], text)
  to anon, authenticated;
