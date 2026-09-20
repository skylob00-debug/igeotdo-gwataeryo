-- 폐지된 규정을 지우지 않고 남긴다
--
-- 지금까지는 별표에서 사라진 행을 publish.py 가 DELETE 했다.
-- 실제로 별표 6 제2의3호가 그렇게 지워졌다. 문제가 셋이다.
--
--   1. 사용자가 저장(즐겨찾기)한 항목이 말없이 사라진다
--   2. "예전엔 과태료였는데 지금도?" 를 확인할 방법이 없다
--   3. 폐지됐다는 사실 자체가 쓸모 있는 정보인데 버려진다
--
-- 그래서 지우는 대신 날짜를 찍는다.
--
--   repealed_at      현행 별표에서 더 이상 확인되지 않게 된 시점
--                    (그 별표의 개정일. 우리가 아는 가장 이른 근거다)
--   repealed_reason  어느 별표 어느 개정에서 확인되지 않았는지
--
-- 앱에서:
--   홈·검색 -> repealed_at is null 만
--   저장함  -> 전부. 폐지된 것은 회색으로 "폐지" 표시
--   알림    -> 저장한 규정이 폐지되면 알려 준다

alter table public.violations
  add column if not exists repealed_at     date,
  add column if not exists repealed_reason text;

comment on column public.violations.repealed_at is
  '폐지일. null 이면 현행. 행을 지우지 않는 이유는 저장(즐겨찾기)이 깨지지 않게 하기 위해서다.';

-- 현행만 보는 질의가 대부분이라 부분 인덱스를 둔다
create index if not exists violations_active_idx
  on public.violations (concept, zone)
  where repealed_at is null;

-- RLS 는 그대로 둔다. 폐지된 행도 anon 이 읽을 수 있어야
-- 저장 목록과 검색에서 "폐지됨" 을 보여줄 수 있다.
