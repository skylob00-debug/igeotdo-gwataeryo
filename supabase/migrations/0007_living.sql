-- 생활 과태료를 실을 수 있게 축을 넓힌다
--
-- 폐기물관리법 시행령 별표 8 은 도로교통법 별표와 표의 축이 다르다.
--
--   도로교통법   위반행위 x 차종            (신호위반 승용 7만 / 승합 8만)
--   생활 과태료   위반행위 x 위반 횟수        (조치명령 미이행 1차 30만 / 2차 70만)
--
-- 차종 축은 그대로 두고 횟수 축을 더한다. 둘을 한 테이블에서 다루는 이유는
-- 앱이 보여주는 것이 결국 "이 행위에 얼마"로 같기 때문이다. 테이블을 가르면
-- 상세 화면과 검색을 두 벌 만들어야 한다.
--
-- offense_count 는 도로교통법에도 곧 필요하다. 2026년 6월 2일 공포된
-- 도로교통법(법률 제21728호) 제160조제3항 후단이 2027년 6월 3일 시행되면,
-- 최초 과태료 처분일부터 1년 이내에 신호·중앙선·속도·횡단보도 위반을 합산
-- 3회 이상 한 경우 100만원 이하 범위에서 횟수에 따라 가중된다. 그때 시행령
-- 별표 6 에 횟수 열이 생긴다. 지금 넣어 두면 두 번 일하지 않는다.
--
-- category / zone 은 이미 있다 (0001, 0003). 새로 만들지 않는다.
--   violations.category  'driving' | 'waste' | 'etc'
--   violations.zone      생활 과태료는 보호구역 개념이 없으므로 'none'

-- ---------------------------------------------------------------------------
-- 1. 위반 횟수 축
-- ---------------------------------------------------------------------------
alter table public.violation_penalties
  add column if not exists offense_count smallint not null default 1
    check (offense_count between 1 and 3);

comment on column public.violation_penalties.offense_count is
  '위반 횟수(1·2·3차 이상). 횟수 구분이 없는 별표는 전부 1 이다. '
  '가중 적용 기간과 감경 규칙은 별표 비고(sources.notes)에 있다.';

-- 기본키에 횟수를 넣는다. 넣지 않으면 1·2·3차가 서로를 덮어쓴다.
alter table public.violation_penalties
  drop constraint if exists violation_penalties_pkey;
alter table public.violation_penalties
  add primary key (violation_id, kind, vehicle_type, offense_count, effective_from);

-- ---------------------------------------------------------------------------
-- 2. 차종 없음
-- ---------------------------------------------------------------------------
-- 담배꽁초를 버리는 데 승용·승합이 없다. 'all'(모든 차마)과는 뜻이 다르므로
-- 값을 따로 둔다. 앱은 'none' 이면 차종 열 자체를 그리지 않는다.
alter table public.violation_penalties
  drop constraint if exists violation_penalties_vehicle_type_check;
alter table public.violation_penalties
  add constraint violation_penalties_vehicle_type_check
  check (vehicle_type in ('car', 'van', 'motorcycle', 'bicycle', 'pm', 'all', 'none'));

-- ---------------------------------------------------------------------------
-- 3. 생활인 대상
-- ---------------------------------------------------------------------------
-- 0004 에서 driver / operator / academy 를 뒀다. 생활 과태료의 홈 대상이
-- 하나 더 필요하다. 별표 8 의 89개 행위 중 7개만 여기 해당한다 —
-- 나머지는 폐기물처리업자·검사기관 대상이라 operator 다.
alter table public.concepts
  drop constraint if exists concepts_audience_check;
alter table public.concepts
  add constraint concepts_audience_check
  check (audience in ('driver', 'operator', 'academy', 'resident'));

comment on column public.concepts.audience is
  '홈 피드는 category 에 맞는 대상만 보여준다. '
  'driving -> driver, waste -> resident. 나머지는 검색으로만 닿는다.';

-- 홈 정렬 인덱스도 갈래를 함께 본다
drop index if exists concepts_sort_idx;
create index if not exists concepts_sort_idx
  on public.concepts (category, audience, awareness_score desc, key);

-- GRANT 는 테이블 단위라 새 컬럼에 자동으로 따라온다. RLS 도 그대로다.
