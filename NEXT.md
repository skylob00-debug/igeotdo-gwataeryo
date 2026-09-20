# 이어서 하기

마지막 작업: 2026-09-19
다시 시작할 때 이 파일부터 읽는다. 자세한 배경은 `plan.txt`.

---

## 지금 상태 — 만드는 일은 끝났다

| | |
|---|---|
| 데이터 | 개념 187 / 위반행위 272 / 금액 823 (도로교통법 + 폐기물관리법) |
| 앱 | 홈(운전·생활) / 검색 / 저장 / 알림 / 상세, 최초 실행 면책 동의 |
| 푸시 | 감지 → 검수 → 발송 → 수신까지 실기기 확인 완료 |
| 서명 | 업로드 키로 서명한 **AAB 준비됨** |
| 스토어 자료 | 스크린샷 6장, 그래픽, 설명문, 처리방침 페이지 전부 있음 |
| 테스트 | 파이프라인 67 + 앱 48, analyze 무경고 |

**남은 것은 만드는 일이 아니라 계정 만들고 올리는 일이다.**

---

## 바로 할 일 (순서대로)

### 1. GitHub 저장소 + Pages — 처리방침 주소 확보

스토어 등록에 **개인정보 처리방침 URL이 필수**다. 이게 없으면 시작을 못 한다.

먼저 `docs/` 의 노란색 표시 세 곳을 채운다.

| 파일 | 채울 것 |
|---|---|
| `docs/privacy.html` | 시행일 |
| `docs/privacy.html` | 개인정보 보호책임자 성명 · 이메일 |
| `docs/index.html` | 맨 아래 문의처 |

> 이메일은 스토어와 방침에 공개된다. 앱 전용으로 하나 만드는 편이 낫다.

그다음 GitHub 에 올린다 (저장소는 사장님이 관리).

```bash
cd C:/Users/USER/DEV/APP/app3
git init
git add .
git commit -m "이것도 과태료? 초기 커밋"
git branch -M main
git remote add origin https://github.com/<아이디>/<저장소>.git
git push -u origin main
```

저장소는 **public**, 그다음 `Settings → Pages → Source` 를 **`main` 브랜치의 `/docs`**.

```
방침 주소  https://<아이디>.github.io/<저장소>/privacy.html
```

**올리기 전 확인**: `.gitignore` 가 `.env`, `*.jks`, `key.properties`,
`app/env.json` 을 막고 있다. `git status` 에 이것들이 안 보이는지 눈으로 본다.

### 2. Play 개발자 계정

<https://play.google.com/console> · $25 일회성.
개인 계정이면 **비공개 테스트 요건**(테스터 인원·기간)이 있다. 정책이 자주
바뀌니 콘솔에서 확인한다.

### 3. 스토어 등록

`store.md` 를 그대로 복사해 채운다.

| 콘솔 항목 | 어디에 |
|---|---|
| 앱 이름 / 간단한 설명 / 자세한 설명 | `store.md` 1~3절 |
| 카테고리 · 태그 | `store.md` 4절 (자동차 권장) |
| 스크린샷 6장 | `design/store/01~06*.png` |
| 그래픽 이미지 | `design/store/feature.png` |
| 앱 아이콘 512 | `app/assets/brand/icon.png` |
| 개인정보 처리방침 URL | 1번에서 받은 주소 |
| 데이터 보안 양식 | `store.md` 8절 — **사실대로. 틀리면 등록 취소** |
| 콘텐츠 등급 | 설문. 전체 이용가로 통과할 내용 |

올릴 파일:

```
app/build/app/outputs/bundle/release/app-release.aab
```

없으면 다시 만든다:

```bash
cd app
flutter build appbundle --release --dart-define-from-file=env.json
```

---

## 나중에 (급하지 않다)

- **상표 출원** — `trademark.md`. 9류·42류·45류 지정상품 초안이 들어 있다.
  출시하고 이름을 계속 쓸 게 확실해진 뒤가 순서에 맞다.
- **웹 버전** — `seed.json` 에서 정적 사이트를 뽑는다. "담배꽁초 과태료 얼마"
  같은 검색 유입을 받는다. 앱보다 이쪽이 사람이 더 올 가능성이 높다.
- **Phase 2 더 넓히기** — 자원재활용법 등. `pipeline/fetch_byeolpyo.py`
  의 `LAWS` 에 한 줄 더하는 것으로 시작한다.

---

## 운영 — 법이 바뀌면

`law-watch` 가 매일 06:00 KST 에 돈다. 자동으로 발송하지 않는다.

1. 앱 알림 탭이나 `law_changes` 테이블에 새 행이 쌓인다 (`published=false`)
2. 원문을 읽고 **제목 60자 / 본문 120자** 안에서 사용자 말로 고친다
3. 게시 방식을 정한다

   | | published | push |
   |---|---|---|
   | 알림까지 보낼 것 | true | true |
   | 목록에만 올릴 것 | true | **false** |
   | 알릴 값이 없는 것 | false | false |

4. 발송

```bash
# 무엇이 나갈지 먼저
node --experimental-strip-types supabase/functions/push-notify/local.ts
# 실제 발송 (배포된 함수 호출)
```

**별표 금액이 바뀌면** 파이프라인이 일부러 멈춘다. 순서는 이렇다.

```bash
.venv/Scripts/python.exe pipeline/fetch_byeolpyo.py   # 원문 재수집
.venv/Scripts/python.exe pipeline/review.py           # 무엇이 바뀌었는지
# 검수 -> overrides.json 과 테스트의 해시·기대값 갱신
.venv/Scripts/python.exe pipeline/publish.py
.venv/Scripts/python.exe pipeline/export_seed.py
```

---

## 자주 쓰는 명령

```bash
# 자료 다시 만들기 (앱 고치기 전에 항상)
.venv/Scripts/python.exe pipeline/export_seed.py

# 검증
.venv/Scripts/python.exe -m pytest -q          # 67개
cd app && flutter test && flutter analyze      # 48개

# 실기기에 올리기
cd app && flutter build apk --release --split-per-abi --dart-define-from-file=env.json
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# 스토어용
cd app && flutter build appbundle --release --dart-define-from-file=env.json
```

> **`flutter install` 을 쓰지 말 것.** 통합 APK 를 올리는데 그게 낡아 있을 수
> 있다. 실제로 Firebase 값이 빠진 판이 올라가 푸시가 안 됐다.
> versionCode 도 달라(통합 1 / arm64 2001) 섞으면 다운그레이드로 막힌다.

---

## 어디에 뭐가 있나

| | |
|---|---|
| `plan.txt` | 분석 근거, 결정 기록, 겪은 문제 — **가장 두꺼운 기록** |
| `CLAUDE.md` | 작업 규약, 하지 말 것 |
| `store.md` | 스토어 등록 자료 전부 |
| `trademark.md` | 상표 지정상품 초안 |
| `docs/` | GitHub Pages (소개 + 처리방침) |
| `design/store/` | 스크린샷 6장, 그래픽 이미지 |
| `pipeline/` | 법령 → 검수 → 적재 |
| `supabase/` | 스키마 7개, Edge Function 2개 |
| `app/` | Flutter |

---

## 잊으면 큰일 나는 것

**업로드 키.** `C:/Users/USER/keys/igeotdo-upload.jks` + 비밀번호.
**잃어버리면 앱을 영영 업데이트할 수 없다.** 저장소가 아닌 곳에 백업.
지금 백업이 되어 있는지 한 번 더 확인할 것.

**Firebase 는 Spark(무료) 유지.** 카드를 등록하지 않으면 청구가 나갈 방법이
없다. FCM 은 애초에 과금 항목이 없다.

**모델을 고치면 `Repository._cacheSchema` 를 올린다.** 안 올리면 옛 캐시가
그대로 읽혀 새 필드가 조용히 기본값으로 채워진다. 실제로 생활 탭이 통째로
비었던 적이 있다.

**금액을 추측하지 않는다.** 원문에서 못 읽으면 `needs_review` 로 넘긴다.
사람이 확인한 값만 `overrides.json` 에 `reason` 과 함께 들어간다.
