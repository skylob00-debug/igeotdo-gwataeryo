# 이것도 과태료?

운전자가 몰라서 무는 과태료·범칙금을 근거 조문·금액·시행일과 함께 알려주고,
도로교통법이 개정되면 알려주는 앱.

앱 이름의 물음표는 스토어 표시명에만 쓴다.
패키지 식별자는 `kr.co.igeotdo.gwataeryo` (android/ios 양쪽 확정. 출시 후 변경 불가).

먼저 읽을 것:
- **`NEXT.md` — 다시 시작할 때 여기부터.** 남은 일과 명령이 순서대로 있다
- `plan.txt` — 분석 근거, 확정된 결정, 겪은 문제
- `pipeline/README.md` — 데이터 파이프라인 상세
- `store.md` / `trademark.md` — 스토어 등록 / 상표 출원

현재 상태: 데이터·백엔드·개정감지·큐레이션 완료. **Flutter 앱 MVP 동작.**
푸시는 실기기 발송까지 확인했다 (`plan.txt` 5.7절). Firebase 프로젝트 `igeotdo-gwataeryo`.
파이프라인 테스트 67개 + 앱 테스트 48개. 실기기(갤럭시 S22 울트라) 확인.
**만드는 일은 끝났다.** 남은 것은 GitHub Pages 올리기(처리방침 URL),
Play 개발자 계정, 스토어 등록뿐이다. 자세한 순서는 `NEXT.md`.

## 두 갈래 코드베이스

```
pipeline/   Python. 법령 -> 검수 -> Supabase + 앱 seed
app/        Flutter. 오프라인 우선, 읽기 전용
docs/       GitHub Pages. 앱 소개 + 개인정보 처리방침
supabase/   스키마(마이그레이션 7개) + Edge Function 2개(law-watch, push-notify)
tools/      make_brand.py — 아이콘·스플래시 원본
```

앱을 고치기 전에 `pipeline/export_seed.py`를 돌려 `app/assets/seed.json`과
`app/env.json`을 최신으로 맞춘다. 둘 다 생성물이라 손으로 고치지 않는다.

```bash
.venv/Scripts/python.exe pipeline/export_seed.py   # seed.json + env.json
cd app && flutter run --dart-define-from-file=env.json
cd app && flutter test && flutter analyze
```

## 절대 규칙

**금액을 추측하지 말 것.** 원문에서 못 읽으면 `needs_review`로 넘긴다.
사람이 확인한 값만 `overrides.json`에 `reason`과 함께 들어간다.
법률 정보라 틀린 금액 하나가 앱 전체의 신뢰를 무너뜨린다.
`curation.json`은 **문구만** 정한다. 거기서 금액을 손대지 않는다.

**PDF 파싱으로 돌아가지 말 것.** HWP를 쓰는 이유는 `plan.txt` 2.2절에 있다.
요약하면 PDF는 줄바꿈에서 한글 띄어쓰기가 사라지고(복구 불가) 셀 병합을 좌표로
추정해야 한다. 이미 시험하고 탈락시킨 경로다.

**개인 과태료 조회 기능을 만들려 하지 말 것.** 이파인은 로그인 기반이고 공개
API가 없다. 딥링크로 보내는 것까지만 한다. 실시간 단속 알림도 불가(개인정보).

**`OC=test`는 테스트 전용.** 운영은 `LAW_API_OC` 환경변수로 발급받은 값을 쓴다.
`.env`에 이미 발급받은 값이 들어 있다.

**`SUPABASE_SERVICE_KEY`를 앱에 넣지 말 것.** RLS를 우회하는 키다. 적재 스크립트 전용.
**Firebase 서비스 계정 JSON도 마찬가지다.** 발송 권한이라 서버에만 둔다.
앱에 들어가는 것은 `FIREBASE_*` 네 값뿐이고 그건 공개 값이다.

**금액을 보여주는 모든 화면에** 근거 조문 + 시행일 + 면책 문구 + 국가법령정보센터
원문 링크를 함께 낸다. 이게 이 앱의 법적 리스크 방어선이다.

## 개발 환경

Windows / PowerShell. venv는 `.venv/Scripts/python.exe`.

콘솔이 cp949라 한글을 출력하는 스크립트는 `PYTHONIOENCODING=utf-8`이 필요하다.
없으면 `UnicodeEncodeError`가 나거나 출력이 깨진다.

```bash
export PYTHONIOENCODING=utf-8

.venv/Scripts/python.exe pipeline/fetch_byeolpyo.py     # 원문 받기 (네트워크)
.venv/Scripts/python.exe pipeline/normalize.py          # out/violations.json
.venv/Scripts/python.exe pipeline/review.py             # out/review.csv (엑셀용)
.venv/Scripts/python.exe pipeline/publish.py --dry-run  # 보낼 내용만 확인
.venv/Scripts/python.exe pipeline/publish.py            # Supabase 적재
.venv/Scripts/python.exe pipeline/check_rls.py          # RLS 검증 (anon 키 필요)
.venv/Scripts/python.exe -m pytest -q                   # 검증 (67개)
```

환경 변수는 `.env`에 둔다(gitignore됨). `config.py`가 읽는다.
`.env.example`에 필요한 항목이 있다.

## 코드 구조

```
fetch_byeolpyo.py   법령 본문조회 API -> 별표내용(.txt) + 별표 HWP(.hwp) + manifest.json
       |
hwptable.py         HWP5 레코드 파싱 -> 표를 행/열/병합(rowSpan) 단위 셀로
       |
extract_tables.py   셀 -> 부과 단위(Unit). 항목/목, 병합 금액, 물려받는 금액
                    별표마다 표 생김새가 달라 Scheme 으로 전략을 고른다
                      cell = 도로교통법 (한 셀에 항목 여럿)
                      row  = 생활 과태료 (한 행이 곧 한 항목, 3단계 번호)
       |
normalize.py        금액 원문 -> 차종별 정수 + overrides.json 적용
       |
review.py           검수용 CSV + 직전 결과와 diff
       |
publish.py          Supabase 적재 (needs_review 있으면 거부)
curation.json       앱에 보여줄 문구. 개념 125개 + 행 183개 매핑 (도로교통법)
curation_living.json  생활 과태료. 개념 62개 + 행 89개
check_rls.py        anon 키로 RLS 동작 확인
```

Edge Function 둘 다 Deno 지만 로직이 웹 표준만 써서 Node 로도 검증한다.
`Deno.*` 는 파일 맨 아래 진입점에서만 쓴다.

```bash
node --experimental-strip-types supabase/functions/law-watch/local.ts     # 개정 감지
node --experimental-strip-types supabase/functions/push-notify/local.ts   # 발송 dry-run
```

`law-watch` 는 매일 06:00 KST 크론. `push-notify` 는 `published=true` 이고
`push=true` 이고 아직 안 보낸 `law_changes` 만 FCM 토픽 `law-changes` 로 쏜다.

**`published` 와 `push` 는 다른 판단이다.** `published`는 앱 알림 목록에 올릴지,
`push`는 그중 폰을 울릴지다. 벌점 개정처럼 훑어볼 값은 있어도 깨울 값은 없는
건이 있다. `push` 기본값은 `true` — 끄는 것을 잊는 손해보다 켜는 것을 잊어
아무에게도 안 가는 손해가 크다.

`tools/make_brand.py`가 아이콘·스플래시 원본을 만든다 (`plan.txt` 5.8절).
색은 `app/lib/core/theme.dart`의 `AppColors`와 같은 값이어야 한다.
원본을 바꾸면 네이티브 리소스를 다시 만들어야 한다.

```bash
.venv/Scripts/python.exe tools/make_brand.py --concepts   # 시안 비교
.venv/Scripts/python.exe tools/make_brand.py --icon coin  # 원본 (확정안)
cd app && dart run flutter_launcher_icons
cd app && dart run flutter_native_splash:create
```

`lawapi.py`가 DRF API 클라이언트, `config.py`가 `.env` 로더다.
`export_seed.py`가 앱 seed 와 env.json 을 만든다.
스키마는 `supabase/migrations/` 아래 5개.

## 앱 구조 (app/lib)

```
core/     env(빌드 인자) theme(색·토큰) format(금액·날짜 표기) push(FCM)
data/     models  remote(PostgREST 읽기)  repository(seed+캐시+저장)  providers
widgets/  concept_card  penalty_table  common(Pill·헤더·면책)
features/ home  search  detail  saved  alerts  consent(최초 1회 면책)
```

**SQLite 를 쓰지 않는다.** 데이터가 200KB 남짓이라 통째로 메모리에 두고
캐시는 JSON 파일 하나다. Phase 2 로 자료가 크게 늘면 `Repository` 안만
바꿔 끼운다. drift 를 넣으면 코드 생성까지 딸려와 지금은 값이 없다.

**금액은 앱에서 계산하지 않는다.** seed 에 있는 값을 그대로 보여줄 뿐이다.

**모델을 고치면 `Repository._cacheSchema`를 올린다.** `data_version`은 자료가
몇 번째인지만 말하고 앱이 읽는 모양이 바뀐 것은 말하지 못한다. 안 올리면 옛
캐시가 그대로 읽혀 새 필드가 기본값으로 조용히 채워진다 (실제로 생활 탭이
통째로 비었다).

**축이 둘이다.** 도로교통법은 `차종`별로, 생활 과태료는 `위반 횟수`(1·2·3차)별로
금액이 갈린다. 한쪽만 있는 데이터는 다른 쪽이 `none`/`1` 이다. 표를 그릴 때
`vehicle == Vehicle.none` 이면 차종 자리에 횟수를 넣는다.

**법령 이름을 화면에 박지 말 것.** 별표 번호만으로는 구분되지 않는다
(도로교통법 별표 8 과 폐기물관리법 별표 8 이 둘 다 있다). `Source.lawName` 을 쓴다.

**최초 실행 면책 동의 전에는 아무것도 하지 않는다.** 갱신 확인도 푸시 등록도
동의 뒤에 시작한다(`_ShellState._begin`). 면책을 읽기도 전에 알림 권한을 묻는
것은 무례하고 거절률도 높다. 문구를 실질적으로 고치면 `Repository.consentVersion`
을 올린다 — 그래야 이미 쓰던 사람에게 다시 한 번 뜬다.

## 작업 규약

**테스트 67개가 기준선이다.** 파서를 고쳤을 때 건수 스냅샷
(`EXPECTED_COUNTS`: 72/7/88/16)이 깨지면 **기대값을 고치기 전에 왜 변했는지부터
확인한다.** 항목을 조용히 흘리는 것을 잡으려고 둔 장치다. 실제로 별표 7·10 을
붙이다가 이 스냅샷이 별표 6 의 누락 1건(제2의3호 이륜 금액)을 잡아냈다.

**스키마를 고치면 세 가지를 같이 본다.** 이 환경엔 Postgres가 없어 SQL을 로컬에서
실행할 수 없다.
1. `test_publish.py`가 `0001_init.sql`을 파싱해 컬럼·CHECK 허용값을 `publish.py`가
   보낼 행과 대조한다 (컬럼을 코드에만 추가하는 사고를 잡는다)
2. 새 테이블에는 **`GRANT`를 반드시 같이 쓴다.** RLS 정책만으로는 접근이 안 된다.
   `service_role`도 RLS는 우회하지만 GRANT는 우회하지 않는다 (403 `42501`)
3. 고친 뒤 `check_rls.py`를 돌려 anon이 보는 것이 의도대로인지 확인한다

**별표가 개정되면 파이프라인이 일부러 멈춘다.** 두 군데에 해시 가드가 있다.
- `tests/test_pipeline.py::test_원문이_바뀌지_않았다`
- `normalize.load_overrides` — 확정값이 낡은 원문에 적용되는 것을 막는다

개정 시 순서: 원문 재수집 -> `review.csv`로 무엇이 바뀌었는지 확인 -> 검수 ->
`overrides.json`과 테스트의 해시·기대값 갱신.

**주석, 문서, 커밋 메시지는 한국어로 쓴다.**

## 하지 말 것

- `pipeline/raw/`, `pipeline/out/` 손으로 수정 (생성물이다. 스크립트로 다시 만든다)
- `overrides.json`에 `reason` 없이 값 추가 (테스트가 막는다)
- 폐지 항목(`삭제 <2014.12.31.>`)을 데이터에 싣기
- 파이프라인이 Supabase에 자동으로 반영하도록 만들기 (검수를 거쳐야 한다)
- 개정 감지 결과를 자동으로 푸시 발송 (타법개정까지 잡혀 알림 스팸이 된다)
- `curation.json`·`curation_living.json`에서 금액 고치기 (금액은 별표에서만 온다)
- 화면에 `'도로교통법 시행령'`을 문자열로 박기 (`Source.lawName`을 쓴다.
  실제로 상세 화면 '출처' 줄이 이래서 틀렸고 위젯 테스트가 잡았다)
- `violation_penalties` 기본키에서 `offense_count`를 빼기 (1·2·3차가 서로를 덮는다)
- 별표 표만 보고 `audience`를 정하기 (조문을 봐야 한다. 생활 과태료 3건이
  표에서는 일반인처럼 보이는데 조문에 "사업활동과 관련하여"·"다량 배출자"
  단서가 있었다. `tests/test_living.py`가 7건으로 고정한다)
- 홈 피드에 `audience != 'driver'` 노출 (학원·운영자 조항이 상위를 덮는다)
- 폐지된 `violations`를 DELETE 하기 (저장한 항목이 사라진다. `repealed_at`을 쓴다)
- 홈·검색에서 `repealed_at is not null` 노출 (폐지된 규정을 현행처럼 보여주면 안 된다)
- `app/assets/seed.json`·`app/env.json` 손으로 고치기 (export_seed.py 가 만든다)
- 앱에서 금액을 계산하거나 반올림하기 (별표 값을 그대로 쓴다)
- 금액을 보여주는 화면에서 면책·근거·시행일 빼기 (widget_test 가 막는다)
- 위젯을 그리지 않는 검사를 `testWidgets`로 쓰기 (가짜 비동기 구역이라
  `Repository.load()`의 rootBundle 읽기가 끝나지 않고 멈춘다. `test`를 쓴다)
- 별표 하나를 위해 `extract_tables`의 공통 경로를 고치기 (`Scheme`을 하나 더
  만든다. 도로교통법 4개는 72/7/88/16으로 고정돼 있고 깨지면 손해가 크다)
- 생활 과태료 값을 문구로 찾아 붙이기 (같은 문구가 금액만 다르게 원문에 네 번
  나온다. 행 위치로 붙인다. `tests/test_living.py`가 막는다)
- `law-watch`에 Deno 전용 API를 로직 안에서 쓰기 (Node 검증이 막힌다. `Deno.*`는 진입점에만)
- 크론 정의에 service key를 직접 박기 (`cron.job` 테이블에 평문으로 남는다. Vault를 쓴다)
- `google-services.json`을 `app/android/`에 넣기 (Gradle 플러그인이 딸려 와서
  파일 없는 빌드가 깨진다. 값만 `--dart-define`으로 넘긴다)
- `law_changes` 문구를 law-watch가 넣은 채로 게시하기 (운영자용 문구다.
  원문을 읽고 사용자 말로 바꾼다. 제목 60자·본문 120자, 시행일은 카드가 보여준다)
- 아이콘 원본을 손으로 고치기 (`tools/make_brand.py`가 만든다)
- `adaptive_icon_foreground_inset`을 지우기 (기본 16%가 전경을 한 번 더 줄여
  적응형 아이콘만 네모 아이콘보다 작아진다)
- `values*/styles.xml`의 `NormalTheme`을 `?android:colorBackground`로 되돌리기
  (다크 모드에서 스플래시와 첫 프레임 사이에 검정이 번쩍인다)
- Android 12 스플래시에 `icon_background_color` 주기 (보이는 영역이 768→512로
  줄고, 종이색 위에 종이색 원이라 값이 없다)
- 알림 채널 이름을 세 곳 중 한쪽만 고치기 (`MainActivity`가 만드는 채널,
  manifest의 `default_notification_channel_id`, push-notify의 `channel_id`가
  모두 `law_changes`여야 한다. manifest만으로는 채널이 만들어지지 않는다)
- 실기기에 `flutter install`로 올리기 (통합 APK를 올리는데 그게 낡아 있을 수
  있다. `--split-per-abi`로 뽑아 `adb install -r`로 arm64 판을 올린다.
  versionCode가 달라 둘을 섞으면 다운그레이드로 막힌다)
