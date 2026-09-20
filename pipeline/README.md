# 데이터 파이프라인

도로교통법 시행령 별표에서 과태료·범칙금 금액을 뽑아 앱이 쓸 JSON 으로 만든다.

## 왜 이렇게 만들었나

과태료 금액의 법적 원천은 **도로교통법 시행령 별표 6(과태료)과 별표 8(범칙금)** 이다.
법제처 OPEN API 는 별표를 **텍스트로 주지 않는다** — 별표 목록 API 는 제목과
HWP/PDF 다운로드 링크만 돌려준다. 그래서 앱이 실시간으로 금액을 조회하는 구조는
성립하지 않고, 원본을 한 번 뜯어 DB 로 만든 뒤 개정을 감지하는 방식을 쓴다.

원본 형식은 세 가지를 검토했다.

| 원천 | 띄어쓰기 | 셀 병합 구조 | 결론 |
|---|---|---|---|
| 별표 HTML (`lsBylInfoP.do`) | — | — | JS 렌더링이라 서버에서 못 읽는다 |
| 별표 PDF | ✗ 줄바꿈에서 소실 | ✗ 좌표로 추정해야 함 | 탈락 |
| **별표 HWP** | ✓ 문단 원문 | ✓ `rowSpan`/`colSpan` | **채택** |

PDF 는 표를 좌표로 복원해야 하고, 줄바꿈 지점에서 한글 띄어쓰기가 사라진다
("운전자의 의무" → "운전자의의무"). HWP 는 레이아웃 줄바꿈이 없는 문단 텍스트와
표 셀의 병합 정보를 모두 갖고 있어, 어느 위반행위가 어느 금액을 쓰는지 정확하다.

법령 API 의 `<별표내용>` 이 주는 박스아트 표(`┏━┯━┓`)도 함께 받아 둔다.
셀 병합 정보가 없어 추출에는 쓰지 않지만, 원문이 바뀌었는지 판단하는
해시 기준으로 쓴다.

## 흐름

```
fetch_byeolpyo.py   법령 본문조회 API -> 별표내용(.txt) + 별표 HWP(.hwp) + manifest.json
       |
hwptable.py         HWP5 레코드 파싱 -> 표를 행/열/병합 단위 셀로
       |
extract_tables.py   셀 -> 부과 단위(Unit). 항목/목, 병합 금액, 물려받는 금액 처리
       |
normalize.py        금액 원문 -> 차종별 정수 + overrides.json 적용. out/violations.json
       |
review.py           out/review.csv (사람이 원문과 대조). 직전 결과와 diff
       |
publish.py          Supabase 적재. 검수가 안 끝났으면 거부한다
                    curation.json 의 문구를 여기서 붙인다
```

## 실행

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r pipeline/requirements.txt
cp .env.example .env          # 값을 채운다

.venv/Scripts/python pipeline/fetch_byeolpyo.py   # 원문 받기
.venv/Scripts/python pipeline/normalize.py        # out/violations.json
.venv/Scripts/python pipeline/review.py           # out/review.csv
.venv/Scripts/python pipeline/publish.py --dry-run  # 보낼 내용만 확인
.venv/Scripts/python pipeline/publish.py            # Supabase 적재
.venv/Scripts/python -m pytest                    # 검증
```

## 환경 변수

`.env` 는 gitignore 된다. `.env.example` 을 복사해 값을 채운다.
`config.py` 가 읽어서 `os.environ` 에 채우되, 이미 셸에 설정된 값은 덮어쓰지 않는다.

| 이름 | 용도 |
|---|---|
| `LAW_API_OC` | 법제처 OPEN API 인증. 비우면 `test`(테스트 전용)로 동작한다 |
| `SUPABASE_URL` | `publish.py` 적재 대상 |
| `SUPABASE_SERVICE_KEY` | `sb_secret_...`. RLS 를 우회하므로 **앱에 넣지 말 것** |
| `SUPABASE_ANON_KEY` | `sb_publishable_...`. 공개 키라 앱에 들어간다. RLS 검증용 |

OC 는 [국가법령정보 공동활용](https://open.law.go.kr/LSO/openApi/openApiManual.do)
에서 신청한다 (신청 이메일 ID 앞부분). 문의 02-2109-6446.

## 현재 결과 (2026-09 기준)

| 별표 | 개정일 | 부과 단위 | 자동 | 사람이 확정 | 미해결 |
|---|---|---|---|---|---|
| 별표 6 (과태료) | 2025. 3. 18. | 72 | 63 | 9 | 0 |
| 별표 7 (보호구역 과태료) | 2020. 12. 1. | 7 | 7 | 0 | 0 |
| 별표 8 (범칙금) | 2025. 6. 2. | 88 | 88 | 0 | 0 |
| 별표 10 (보호구역 범칙금) | 2022. 7. 11. | 16 | 16 | 0 | 0 |
| **합계** | | **183** | 174 | 9 | 0 |

금액 행은 556건(차종별). 별표 7·10 은 어린이·노인·장애인보호구역판으로,
같은 위반이라도 일반 도로보다 금액이 높다 (신호위반 승용 범칙금 6만 -> 12만).

폐지된 항목(`삭제 <2014.12.31.>`)은 싣지 않는다.

## 자동으로 못 푸는 경우

금액을 추측하지 않는다. 못 읽은 건 `needs_review` 로 표시하고,
사람이 확인한 값은 `overrides.json` 에 근거와 함께 적는다.

**목이 4개인데 금액 묶음이 2개** (별표 6 제4의2호·제6의4호, 8건)
항목과 목이 한 셀에 문단으로 들어 있고 금액도 한 셀에 두 묶음으로 들어 있다.
어느 목이 어느 금액인지는 **데이터에 없고 렌더링 위치로만 구분된다.**
두 가지 근거가 일치해 확정했다.

  - 과태료 = 같은 위반의 범칙금(별표 8) + 1만원
    (신호위반 6만/7만, 속도 60㎞/h 초과 12만/13만으로 이미 검증된 규칙)
  - 법제처 별표내용(박스아트) 렌더링에서 금액 묶음이 찍힌 줄 위치

**누진 과태료** (별표 6 제10의3호 나목, 1건)
"10만원에 3일을 초과할 때마다 10만원을 더한 금액" 은 정수 하나로 표현되지 않는다.
기준금액은 `amount_krw`, 가산 규칙은 `penalty_formula` 텍스트로 나눠 담는다.

## overrides.json

사람이 확정한 값은 추출 결과를 덮어쓴다. 다만 확정 당시의 별표 sha256 을 함께
적어 두므로, **원문이 개정되면 파이프라인이 멈춘다.** 옛 판단을 새 원문에 조용히
적용하는 사고를 막기 위해서다. 개정 시에는 다시 검토한 뒤 해시를 갱신한다.
overrides 에만 있고 추출 결과에 없는 id 가 생겨도 멈춘다.

## Supabase 적재 (publish.py)

스키마는 `supabase/migrations/0001_init.sql` 이다.

```
sources              별표 단위 출처. 개정 감지 기준이자 앱 면책 표기의 근거.
                     비고(notes)가 여기 들어간다 — 차종 정의와 2시간 가중 조건이
                     비고에 있어서 앱이 반드시 보여줘야 한다.
concepts             위반 개념. 125건. 앱 카드 하나가 개념 하나다.
violations           부과 단위. 183건. concept 과 zone 으로 카드에 묶인다.
violation_penalties  차종별 금액. 556건. kind(과태료/범칙금)는 여기 있다.
law_watch            개정 감시 상태
law_changes          감지된 변경. published=true 여야 앱에 나간다.
devices              FCM 토큰. 등록은 register_device() 함수로만 한다.
data_version         앱 델타 동기화용
```

적재 순서와 이유:

1. `sources` upsert
2. `concepts` upsert
3. `violations` upsert
4. 이번에 사라진 `violations` 에 **폐지 표시** (지우지 않는다. 아래 참조)
5. 해당 `violations` 의 `violation_penalties` 를 **지우고 다시 삽입**
   upsert 만으로는 이번에 없어진 차종 행이 남는다
6. `data_version` 증가

### 폐지된 규정은 지우지 않는다

처음에는 별표에서 사라진 행을 `DELETE` 했다. 실제로 별표 6 제2의3호가 그렇게
지워졌다. 저장(즐겨찾기) 기능을 넣기로 하면서 이 방식은 못 쓰게 됐다.

| 지우면 | 남기면 |
|---|---|
| 저장한 항목이 말없이 사라진다 | 회색으로 "폐지됨" 을 보여준다 |
| "예전엔 과태료였는데?" 를 확인할 수 없다 | 검색으로 닿는다 |
| 폐지 사실이 버려진다 | 알림으로 알릴 수 있다 |

```sql
repealed_at      폐지일. 별표 개정일을 쓴다
repealed_reason  "별표 6 <개정 2025. 3. 18.> 에서 확인되지 않음"
```

폐지일을 "우리가 발견한 날"로 하지 않은 이유는, 그건 우리 사정이지 법의 사실이
아니기 때문이다. 다만 그 개정에서 정확히 언제 없어졌는지까지는 알 수 없어
`repealed_reason` 에 "확인되지 않음" 이라고 적어 과잉 주장을 피한다.

개정으로 조항이 되살아나면 `repealed_at` 을 해제한다. 폐지된 행의 금액도
남겨 둔다 — 그때는 얼마였는지 보여주기 위해서다.

앱 질의 규칙:

```
홈·검색   repealed_at is null 만
저장함    전부. 폐지된 것은 회색 + "폐지" 표시
알림      저장한 규정이 폐지되면 알려 준다
```

`needs_review` 가 하나라도 있으면 적재를 거부한다.
`out/violations.json` 을 읽지 않고 `normalize.build()` 를 직접 호출하므로,
생성물이 낡아 있어도 상관없고 overrides 의 원문 해시 가드도 같이 걸린다.

두 번 돌려도 안전하다. 확인했다 — 행 수는 그대로고 `data_version` 만 올라간다.

### GRANT 를 빠뜨리지 말 것

RLS 정책만으로는 접근이 안 된다. PostgreSQL 은 두 관문을 다 통과해야 한다.

| 관문 | 정하는 것 |
|---|---|
| `GRANT` | 테이블에 손댈 수 있는가 |
| RLS 정책 | 그중 어떤 **행**을 볼 수 있는가 |

처음에 정책만 쓰고 GRANT 를 빠뜨려 `service_role` 키로도 403 (`42501`) 이 났다.
service_role 은 RLS 를 우회하지만 **GRANT 는 우회하지 않는다.**

### RLS 검증

```bash
.venv/Scripts/python pipeline/check_rls.py
```

`service_role` 키로는 RLS 를 우회하므로 검증이 되지 않는다.
실제 `anon` 키로 REST 를 호출해 앱이 타는 경로 그대로 확인한다.
스키마나 정책을 고치면 반드시 다시 돌린다.

## 큐레이션 (curation.json)

별표 원문은 법문이라 그대로 읽히지 않는다.
"법 제5조를 위반하여 신호 또는 지시를 따르지 않은 차 또는 노면전차의 고용주등"
같은 문장을 앱에 그대로 내보낼 수는 없다.

`curation.json` 이 개념 125개의 제목·한줄설명·분류·점수를 정하고,
별표 행 183개를 개념에 매핑한다. **금액은 손대지 않는다.** 금액은 별표에서만 온다.

### 왜 개념으로 묶는가

같은 위반이 별표에서 최대 네 번 나온다 — 과태료/범칙금 x 일반/보호구역.
행을 그대로 카드로 만들면 검색에 "신호위반"이 네 개 나와 사용자가 헷갈린다.
한 개념으로 묶으면 카드 하나가 전체 그림을 보여준다.

```
신호·지시 위반
  일반도로   범칙금 승용  6만 / 과태료 승용  7만
  보호구역   범칙금 승용 12만 / 과태료 승용 13만
```

"보호구역은 2배"가 카드 안에서 저절로 드러난다. 따로 설명할 필요가 없다.

### zone

별표 7·10 의 목이 곧 보호구역 구분이다. 이게 없으면 카드에서
어린이보호구역(승용 12만)과 노인·장애인보호구역(승용 8만)을 구분할 수 없다.
`publish.zone_of()` 가 `action` 텍스트에서 도출한다.

### audience

`awareness`(몰랐을 가능성) 하나로 홈을 정렬했더니 학원 운영자 대상 과태료가
상위를 덮었다. 일반 운전자가 모르는 게 당연하고 알 필요도 없는 항목이다.
**모른다는 것과 나와 상관있다는 것은 다른 축이다.**

`driver`(101) / `operator`(18) / `academy`(6) 으로 나눠 홈은 driver 만 보여준다.
나머지는 검색으로 닿는다.

### 적재가 거부되는 경우

- 개념 매핑이 없는 행이 있다
- 정의되지 않은 개념을 가리킨다
- 쓰이지 않는 개념이 있다
- **같은 칸(개념·종류·구역·차종)에 금액이 둘 이상이다**
  카드 표에 무엇을 쓸지 정할 수 없다는 뜻이다. 개념을 나눠야 한다.
  실제로 특별교통안전교육(재위반 15만 / 그 외 10만)이 이 검사에 걸려 나뉘었다.

## 개정을 감지하는 방법

두 겹이다.

**로컬** — `manifest.json` 에 별표내용과 HWP 의 sha256 을 기록해 둔다.
`fetch_byeolpyo.py` 를 다시 돌려 해시가 달라지면 별표가 개정된 것이다.
`tests/test_pipeline.py::test_원문이_바뀌지_않았다` 가 이를 잡아내므로,
개정 시에는 **검수를 거친 뒤** 테스트의 기대값을 갱신한다.

**클라우드** — `supabase/functions/law-watch/` 가 매일 돌면서 감시한다.

### law-watch Edge Function

매일 06:00 KST 에 세 가지를 본다.

| 감지 | `change_type` | 뜻 |
|---|---|---|
| MST·시행일자 변화 | `amended` | 법령이 개정됐다 |
| 별표 내용 해시 변화 | `byeolpyo_changed` | 금액이 바뀌었을 수 있다. 파이프라인 재실행 신호 |
| 미래 시행일 법령 | `upcoming` | "○월 ○일부터 이렇게 바뀝니다" |

감지만 하고 **알림은 보내지 않는다.** `law_changes` 에 `published=false` 로 쌓이고,
사람이 문구를 다듬어 `published=true` 로 바꿔야 앱과 푸시에 나간다.
법령 API 는 자잘한 타법개정까지 잡아내므로 그대로 쏘면 알림 스팸이 된다.

첫 실행은 기준선만 세운다. 없던 변화를 만들어 내지 않는다.
같은 시행 예정 법령을 매일 다시 쌓지도 않는다.

#### 로컬에서 검증하기

로직은 웹 표준(`fetch`, `crypto.subtle`)만 쓴다. Deno 전용 코드는 진입점뿐이라
Node 로 같은 코드를 그대로 돌려 볼 수 있다.

```bash
node --experimental-strip-types supabase/functions/law-watch/local.ts          # dry-run
node --experimental-strip-types supabase/functions/law-watch/local.ts --write  # 실제 기록
```

#### 배포

Supabase CLI 가 있으면 `supabase functions deploy law-watch`.
없으면 Dashboard > Edge Functions > Deploy a new function > Via Editor 에서
`index.ts` 내용을 붙여 넣는다. **이름은 반드시 `law-watch`** — 크론이 이 경로를 부른다.

Edge Function Secrets (프로젝트 전체 공용) 에 두 개를 넣는다.

| 이름 | 값 |
|---|---|
| `LAW_API_OC` | 법제처에서 발급받은 OC |
| `CRON_SECRET` | 함수를 부를 때 쓸 임의 문자열 (`.env` 와 같은 값) |

`SUPABASE_URL` 과 서비스 키는 Supabase 가 자동으로 넣는다.

**Verify JWT 를 꺼야 한다.** 켜 두면 게이트웨이가 함수 코드에 닿기 전에
`UNAUTHORIZED_INVALID_JWT_FORMAT` 으로 막는다. `CRON_SECRET` 이 JWT 가 아니기
때문이다. 꺼도 함수 코드 안의 `CRON_SECRET` 검사가 남아 있어 아무나 못 부른다.
실제로 확인했다 — 틀린 시크릿과 헤더 없는 호출 모두 401 이다.

왜 서비스 키를 그대로 쓰지 않고 `CRON_SECRET` 을 따로 두는가:
이 프로젝트는 새 형식 키(`sb_secret_...`)를 쓰는데 Supabase 가 함수에 주입하는
환경변수는 구형식 기준이라 값이 서로 다를 수 있다. 전용 시크릿이 확실하다.

배포 확인:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/law-watch?dry=1" \
     -H "Authorization: Bearer $CRON_SECRET"
```

#### 스케줄

Dashboard > Integrations > Cron 에서 만드는 쪽이 간단하다
(매일 21:00 UTC = 06:00 KST, law-watch 함수 호출).

SQL 로 하려면 `supabase/migrations/0002_law_watch_cron.sql` 을 쓴다.
Vault 에 `project_url` 과 `service_key` 를 먼저 넣어야 한다 —
크론 정의에 키를 직접 박으면 `cron.job` 테이블에 평문으로 남는다.
