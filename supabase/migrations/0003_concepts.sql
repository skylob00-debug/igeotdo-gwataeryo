-- 위반 개념 (앱 카드 단위)
--
-- 같은 위반이 별표에서 최대 네 번 나온다.
--   과태료(별표 6) / 범칙금(별표 8) x 일반도로 / 보호구역(별표 7·10)
-- 별표 행을 그대로 카드로 만들면 "신호위반"이 네 개 나와 사용자가 헷갈린다.
-- 개념으로 묶어 카드 하나에 표로 보여준다.
--
--   신호·지시 위반
--     일반   범칙금 승용  6만 / 과태료 승용  7만
--     보호구역 범칙금 승용 12만 / 과태료 승용 13만
--
-- 문구(title, summary)는 pipeline/curation.json 에서 온다. 금액은 손대지 않는다.

create table if not exists public.concepts (
  key             text primary key,        -- 'signal'
  title           text not null,           -- '신호·지시 위반'
  summary         text,                    -- 언제 걸리는지 한 줄
  category        text not null default 'driving'
                    check (category in ('driving', 'waste', 'etc')),
  subcategory     text,                    -- '속도' '주정차' '보행자' 등
  awareness_score int  not null default 0  -- '몰랐을 가능성' 0~100. 홈 정렬용
    check (awareness_score between 0 and 100),
  search_text     text generated always as (
                    title || ' ' || coalesce(summary, '') || ' ' || coalesce(subcategory, '')
                  ) stored,
  updated_at      timestamptz not null default now()
);

create index if not exists concepts_sort_idx
  on public.concepts (awareness_score desc, key);
create index if not exists concepts_search_idx
  on public.concepts using gin (search_text gin_trgm_ops);

drop trigger if exists concepts_touch on public.concepts;
create trigger concepts_touch before update on public.concepts
  for each row execute function public.touch_updated_at();


-- ---------------------------------------------------------------------------
-- violations 에 개념과 구역 구분을 붙인다
--
-- zone 이 없으면 보호구역 카드에서 어린이(12만)와 노인·장애인(8만)을 구분할 수
-- 없다. 별표 7·10 의 목이 그 구분이다.
-- ---------------------------------------------------------------------------
alter table public.violations
  add column if not exists concept text references public.concepts(key),
  add column if not exists zone    text not null default 'none'
    check (zone in ('none', 'school', 'senior', 'both'));

comment on column public.violations.zone is
  'none=일반도로, school=어린이보호구역, senior=노인·장애인보호구역, both=보호구역 공통';

-- 큐레이션 문구는 concepts 로 옮겼다. violations 에 있던 것은 지운다.
-- search_text 가 title·summary 를 참조하므로 먼저 걷어낸다.
drop index if exists violations_search_idx;
alter table public.violations
  drop column if exists search_text,
  drop column if exists title,
  drop column if exists summary,
  drop column if exists subcategory,
  drop column if exists awareness_score;

alter table public.violations
  add column if not exists search_text text generated always as (
    action || ' ' || parent_action || ' ' || legal_basis || ' ' || ref
  ) stored;

create index if not exists violations_search_idx
  on public.violations using gin (search_text gin_trgm_ops);
create index if not exists violations_concept_idx
  on public.violations (concept, zone);


-- ---------------------------------------------------------------------------
-- 권한 (0001 과 같은 원칙: 읽기는 anon, 쓰기는 service_role)
-- ---------------------------------------------------------------------------
grant select on public.concepts to anon, authenticated;
grant all    on public.concepts to service_role;

alter table public.concepts enable row level security;

drop policy if exists concepts_read on public.concepts;
create policy concepts_read on public.concepts
  for select to anon, authenticated using (true);
