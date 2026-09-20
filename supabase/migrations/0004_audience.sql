-- 개념의 적용 대상
--
-- '몰랐을 가능성'만으로 홈을 정렬했더니 학원 운영자 대상 과태료가 상위를 덮었다.
-- 일반 운전자는 평생 볼 일이 없는 항목인데 "몰랐을 가능성"만 100에 가까우니
-- 당연한 결과다. 모른다는 것과 나와 상관있다는 것은 다른 축이다.
--
--   driver    일반 운전자. 홈 피드는 이것만 보여준다.
--   operator  어린이통학버스·사업용 차량 운영자, 긴급자동차 운전자 등
--   academy   운전학원, 교통안전교육기관
--
-- operator/academy 도 검색으로는 찾을 수 있게 둔다. 지우지 않는다.

alter table public.concepts
  add column if not exists audience text not null default 'driver'
    check (audience in ('driver', 'operator', 'academy'));

comment on column public.concepts.audience is
  '홈 피드는 audience = driver 만 보여준다. 나머지는 검색으로만 닿는다.';

drop index if exists concepts_sort_idx;
create index if not exists concepts_sort_idx
  on public.concepts (audience, awareness_score desc, key);
