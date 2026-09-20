-- law-watch Edge Function 을 매일 돌린다.
--
-- 먼저 Edge Function 을 배포해야 한다 (supabase/functions/law-watch/).
-- 배포 방법은 pipeline/README.md 의 "개정 감지" 절에 있다.
--
-- 이 파일을 실행하기 전에 Vault 에 값 두 개를 넣는다. SQL Editor 에서 한 번만:
--
--   select vault.create_secret('https://<프로젝트>.supabase.co', 'project_url');
--   select vault.create_secret('<service_role 키>',              'service_key');
--
-- 키를 크론 정의에 직접 박지 않는 이유는, cron.job 테이블이 평문으로 남기 때문이다.
--
-- 주의: 이 파일은 Postgres 가 없는 환경에서 작성돼 실행 검증을 하지 못했다.
--       로직 자체(runLawWatch)는 Node 로 실제 API·DB 를 상대로 검증했다.

create extension if not exists pg_cron;
create extension if not exists pg_net;


-- ---------------------------------------------------------------------------
-- Edge Function 호출
-- 응답을 기다리지 않는다. pg_net 이 비동기로 보내고 request_id 를 돌려준다.
-- ---------------------------------------------------------------------------
create or replace function public.run_law_watch()
returns bigint
language plpgsql
security definer
set search_path = public, extensions, vault
as $fn$
declare
  v_url text;
  v_key text;
  v_request_id bigint;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key
    from vault.decrypted_secrets where name = 'service_key';

  if v_url is null or v_key is null then
    raise exception 'Vault 에 project_url / service_key 가 없습니다. 파일 머리말을 보세요.';
  end if;

  select net.http_post(
    url     := rtrim(v_url, '/') || '/functions/v1/law-watch',
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_key),
    body    := '{}'::jsonb,
    timeout_milliseconds := 120000
  ) into v_request_id;

  return v_request_id;
end;
$fn$;

revoke all on function public.run_law_watch() from anon, authenticated;


-- ---------------------------------------------------------------------------
-- 매일 06:00 KST 실행
-- pg_cron 은 UTC 로 돈다. 06:00 KST = 21:00 UTC (전날).
-- ---------------------------------------------------------------------------
select cron.unschedule('law-watch-daily')
  where exists (select 1 from cron.job where jobname = 'law-watch-daily');

select cron.schedule(
  'law-watch-daily',
  '0 21 * * *',
  $cron$select public.run_law_watch()$cron$
);


-- 확인용
--   select jobid, jobname, schedule, active from cron.job;
--   select * from cron.job_run_details order by start_time desc limit 5;
--   select id, status_code, content from net._http_response order by created desc limit 5;
--
-- 수동으로 한 번 돌려보기
--   select public.run_law_watch();
