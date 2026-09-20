-- 게시와 발송을 가른다
--
-- 지금까지 published 하나가 두 가지를 같이 정했다.
--   1. 앱 알림 목록에 나오는가
--   2. FCM 푸시를 쏘는가
--
-- 둘은 같은 판단이 아니다. 실제로 걸린 예가 있다. 시행규칙 별표 28 개정은
-- 긴급자동차 관련 벌점이 신설되는 건인데, 벌점은 이 앱이 다루지 않는다.
-- 앱에 들어와서 훑어볼 사람에게는 알릴 값이 있지만, 자고 있는 사람 폰을
-- 울릴 값은 아니다. 지금 구조로는 "목록에는 올리되 푸시는 안 보냄" 을
-- 표현할 수 없어서 둘 중 하나를 포기해야 했다.
--
--   published  앱 알림 목록에 나오는가   (사람이 검수해 켠다)
--   push       그중 푸시까지 보내는가    (기본 켬)
--
-- 기본값을 true 로 두는 이유는 지금까지의 동작과 같게 하기 위해서다.
-- 알릴 값이 없는 건만 끄면 된다. 반대로 두면 켜는 것을 잊어 조용히
-- 아무에게도 안 가는 사고가 난다 — 잊어서 생기는 손해가 더 큰 쪽을 기본으로.
--
-- push 는 published 를 대신하지 않는다. 둘 다 켜져야 나간다.
-- 제약으로 묶지 않는 이유는, law-watch 가 넣는 새 행이 published=false 이고
-- push 는 기본 true 라 정상 상태에서도 둘이 어긋나 있기 때문이다.
-- 실제 차단은 push-notify 의 질의가 한다 (published=is.true & push=is.true).

alter table public.law_changes
  add column if not exists push boolean not null default true;

comment on column public.law_changes.push is
  'published 된 것 중 FCM 까지 보낼지. 앱 목록에만 올리고 푸시는 참을 때 false.';

-- 보낼 것을 찾는 질의(published=true and push=true and notified_at is null)용.
-- 대부분의 행이 조건에서 빠지므로 부분 인덱스가 맞다.
create index if not exists law_changes_pending_push_idx
  on public.law_changes (created_at)
  where published and push and notified_at is null;

-- GRANT 는 테이블 단위라 새 컬럼에 자동으로 따라온다. RLS 도 그대로 둔다.
-- anon 은 published=true 만 보고, push 는 앱이 읽지 않는다(질의에서 뺀다).
