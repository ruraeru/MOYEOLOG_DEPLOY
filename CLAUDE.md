# MOYEOLOG 배포 레포

메모·일정·모임·친구 서비스 MOYEOLOG의 Docker 배포 구성. 프론트(Next.js)와 백엔드(Spring Boot)는 서브모듈이다.

- 운영 주소: https://moyeolog.ruraeru.xyz
- 서브모듈: `MOYEOLOG_FE` (github.com/ruraeru/MOYEOLOG_FE), `MOYEOLOG_BE` (github.com/ruraeru/MOYEOLOG_BE)
- 브랜치: 세 레포 모두 `main`. `fix/qa-findings`(2026-11-12), FE `design/unslop`(2026-11-14), `fix/qa2`(2026-11-23), FE `design/unslop-2`(2026-11-24) 는 PR 로 머지했다(merge commit, 브랜치는 남겨 둠). 실서비스는 `main` 과 같은 코드로 돌고 있다.

## 구조

```
외부 Caddy(TLS, 172.30.1.10) ─ moyeolog.ruraeru.xyz ─▶ 이 서버 :3003 ─▶ nginx ─┬─ /api, /uploads ─▶ app:8080 (Spring Boot)
                                                                              └─ /api/auth, /api/search-image, /api/proxy-image, 그 외 ─▶ frontend:3000 (Next.js)
                                                        127.0.0.1:8083 ─▶ app:8080 (서버 안에서만 백엔드 직접 접근)
```

- TLS는 외부 Caddy가 종료한다. 이 스택은 HTTP만 다룬다 (certbot 없음).
- 3003은 프론트 컨테이너가 아니라 nginx다. 브라우저가 같은 도메인의 `/api` 를 호출하므로 nginx가 경로로 나눈다.
- 같은 서버에 다른 프로젝트가 3000~3002, 8080~8082 를 쓰고 있다.
- 8083 은 `127.0.0.1` 에만 연다(LAN·tailscale 에서 nginx 를 우회하지 못하게). 3003 은 Caddy 가 다른 호스트라 LAN 에 열어 둔다(`FRONTEND_BIND` 로 좁힐 수 있음).
- 컨테이너: `moyeolog-nginx`, `moyeolog-frontend`, `moyeolog-app`, `moyeolog-db` (MySQL 8.0). compose 프로젝트 이름은 `moyeolog`.

## 실행

```bash
cp .env.example .env        # 값 채우기 (.env 는 gitignore 대상)
git submodule update --init
docker compose up -d --build
```

- `NEXT_PUBLIC_*` 값은 프론트 빌드 시점에 번들에 들어간다. 바꾸면 `--build` 로 다시 빌드해야 한다.
- 프론트/백엔드 컨테이너를 재생성한 뒤에는 `docker exec moyeolog-nginx nginx -s reload` 를 한다 (upstream IP 갱신).
- 호스트에 node, JDK 가 없다. 검증은 Docker 로 한다.
  - 백엔드 테스트: `docker run --rm -v "$PWD":/src -w /src eclipse-temurin:25-jdk-alpine ./gradlew test --no-daemon` (H2 사용, 144개)
  - 프론트 타입 검사: `node:20-alpine` 컨테이너에서 `npm ci && npx tsc --noEmit`
- DB 접속: `docker exec moyeolog-db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" moyeolog'`
- 백업: `backup.sh` (DB + 업로드 볼륨 → `data/backup/`, 14일 보존, 권한 600). 매일 04:00 crontab 으로 돈다(2026-11-23 등록, 로그 `data/backup/backup.log`). 수동 덤프도 `data/backup/` (gitignore 대상).

## 꼭 알아야 할 것

- **백엔드에 `application.yml` 이 없다** (gitignore). 운영 설정은 전부 `docker-compose.yml` 의 환경변수로 들어간다. 새 프로퍼티는 `@Value` 기본값을 주고 `application.yml.example` 과 compose 에 추가한다.
- **`INTERNAL_API_SECRET`**: 프론트 서버(NextAuth)가 백엔드 `POST /api/auth/sync`·`POST /api/auth/logout` 을 부를 때 `X-Internal-Secret` 헤더로 보낸다. 프론트·백엔드 컨테이너에 같은 값이 있어야 로그인이 된다. nginx 는 `/api/auth/sync`, `/api/auth/refresh`, `/api/auth/logout` 을 외부에 404 로 막는다.
- **계정 연결**: 로그인은 kakaoId 로 찾는다. 못 찾으면 Kakao 가 '검증됨'으로 넘긴 이메일이고, 그 이메일의 기존 계정이 아직 한 번도 연결되지 않았을 때(`users.kakao_linked_at IS NULL`)만 그 계정에 붙인다(Kakao 앱 교체 때 기존 사용자 이전용). 그 밖에는 새 계정.
- **토큰**: 로그아웃하면 그 기기의 리프레시 토큰을 지우고 액세스 토큰 jti 를 만료까지 거부한다(`revoked_access_tokens`). '모든 기기 로그아웃'은 `users.tokens_valid_after` 이전 토큰을 거부. `exp` 없는 토큰·typ 없는 예전 토큰은 거부(`JWT_ACCEPT_LEGACY_TOKENS` 기본 false).
- **시간**: 일정 시각과 작성 시각은 오프셋 없는 한국 시간 `LocalDateTime` 이다. 백엔드 컨테이너는 `TZ=Asia/Seoul`. 프론트는 `yyyy-MM-dd'T'HH:mm:ss` 로 보낸다 (`toISOString()` 금지).
- **스키마**: `ddl-auto=update`. Hibernate 는 기존 컬럼 타입을 바꾸지 않으므로 타입 변경은 직접 `ALTER TABLE` 해야 한다.
- **nginx `add_header`**: location 안에 `add_header` 가 하나라도 있으면 server 레벨 헤더가 전부 빠진다. 그런 location 에는 `include /etc/nginx/snippets/security-headers.conf;` 를 넣는다.
- **nginx snippets**: `proxy.conf`(공통 프록시 헤더 + 백엔드·프론트가 보내는 보안 헤더 숨김 → 중복 없이 nginx 것 하나만), `json-errors.conf`(nginx 가 만드는 413·429 를 JSON 으로). 본문 한도는 10m(백엔드와 같음) — 넘으면 바로 JSON 413. `/_next/image` 에도 별도 rate limit.
- **신뢰 프록시**: `set_real_ip_from 172.30.1.10` (Caddy) 하나만 신뢰한다. Caddy 주소가 바뀌면 nginx 접속 로그의 `peer=` 값을 보고 고친다. 범위를 넓히면 `X-Forwarded-For` 조작으로 rate limit 이 우회된다.
- **CSP**: `nginx/conf.d/default.conf` 에 있다. Kakao 지도 SDK 는 `*.kakaocdn.net` 에서 스크립트를 받는다. 외부 리소스를 추가하면 CSP 도 고친다.
- **업로드**: 백엔드가 파일 내용(매직 바이트)으로 JPEG/PNG/GIF/WEBP 만 받고 확장자는 서버가 정한다. nginx 는 `/uploads/` 에서 이미지 확장자만 이미지로 내려주고 나머지는 다운로드로 처리한다. 업로드 볼륨은 uid 1001 소유여야 한다 (백엔드가 non-root 로 실행).
- **알림·메시지**: 백엔드 `notification/`, `message/` 패키지. 다른 서비스는 `event/NotificationEvent` 를 발행만 하고, 리스너가 커밋 뒤 받는 사람 설정을 확인해 저장한다. 메시지는 친구끼리 1:1, 프론트는 5초(대화)·30초(배지) 폴링.
- **회원 탈퇴**: `UserDeletingEvent` 를 동기 발행하면 각 서비스의 리스너가 자기 데이터를 지운다. 방장인 모임은 가장 오래된 멤버에게 넘기고 혼자면 삭제. 새 데이터를 추가하면 그 서비스에도 리스너를 둔다.
- **AI 분석**: 기본은 Ollama 호환 서버(`LLM_BASE_URL`, 기본 `https://ai.ruraeru.xyz`)의 `/api/chat`, 토큰은 `LLM_API_KEY`. Ollama 가 실패(연결·150초 초과·HTTP 오류·형식 오류)하면 `GEMINI_API_KEY` 가 있을 때 Gemini 로 다시 보낸다. 구현은 `GeminiService` 한 곳(이름은 그대로). 분석 요청만 nginx·axios 타임아웃 300초. LLM 을 기다리는 동안 DB 트랜잭션을 잡지 않고(`AiAnalysisSupport`), 같은 대상 분석 중이면 409.
- **Swagger**: 기본으로 꺼져 있다. 필요하면 `.env` 에 `SWAGGER_ENABLED=true`.
- **Kakao 키**: REST API 키(`KAKAO_CLIENT_ID`), Client Secret, JavaScript 키(`NEXT_PUBLIC_KAKAO_MAP_API_KEY`) 는 모두 같은 Kakao 앱의 것이어야 하고, 그 앱에 사이트 도메인과 Redirect URI `https://moyeolog.ruraeru.xyz/api/auth/callback/kakao` 가 등록돼 있어야 한다.
- **git**: 이 서버에는 전역 git 사용자 설정이 없다. 커밋은 `git -c user.name=ruraeru -c user.email=f93335383@gmail.com commit ...` 으로 했다. 푸시는 `gh auth login` 으로 인증돼 있다. 서브모듈을 먼저 푸시하고 배포 레포를 푸시한다.

## 지금까지 한 일 (2026-11-12)

1. **Docker 배포 전환**: `.gitmodules` 복구, 포트 3003/8083 할당, nginx 를 HTTP 단일 서버로 변경, 도메인을 `moyeolog.kro.kr` → `moyeolog.ruraeru.xyz` 로 교체, 백엔드 설정을 환경변수로 주입.
2. **Kakao 연동 정리**: 새 Kakao 앱의 키 3개로 교체, CSP 에 `*.kakaocdn.net` 허용.
3. **QA** (에이전트 3개: 백엔드 API, 보안·배포 설정, 프론트·연동) 후 발견 사항 수정:
   - 보안: `/api/auth/sync` 무인증 계정 탈취, 이미지 프록시 SSRF, 업로드 저장형 XSS, 그룹 비멤버의 메모·일정 읽기/쓰기, rate limit 우회, 보안 헤더 누락.
   - 기능: 설정 페이지 401, 일정 9시간 밀림, 토큰 갱신 후 401 고착, 초대 중복 수락, 이메일 없는 친구 초대 500, 긴 메모 저장 실패, 초대 링크 로그인 후 유실.
   - 권한·설계: 공유받은 메모 읽기 전용, 사용자별 즐겨찾기, 그룹 수정 방장 전용, 오류 응답을 500 대신 4xx 로, 리프레시 토큰 구조 개편.
   - 추가된 API: `DELETE /api/memos/{id}/share/{targetUserId}`, `DELETE /api/groups/{id}/members/me`, `DELETE /api/groups/{id}`. 화면은 2차 QA 때 붙였다.
4. **배포와 재검증**: DB·업로드 백업 후 QA 테스트 데이터 삭제, 컬럼 타입 변경, 새 이미지 배포. QA 에서 재현됐던 항목을 같은 요청으로 다시 확인해 통과.
5. **커밋·푸시·머지**: 세 레포 `fix/qa-findings` → `main` (BE #1, FE #2, DEPLOY #1). 서브모듈 포인터는 각 레포 `main` 의 머지 커밋.

## 화면 디자인 (캠핑 테마, 2026-11-24)

FE PR #6 (`design/unslop-2`)으로 바꿨다. 2026-11-24 운영에 배포했다. Figma 파일 `Xhzk5hq5IlBcQsoi46Fo3r` 의 페이지 "UI 시안 (2026-11-23)" 맨 아래 '캠핑 테마 · 전체 화면'이 기준 시안이다.

- **토큰** (`MOYEOLOG_FE/src/app/globals.css`)
  - 표면 `bg-canvas/surface/raised`, 글자 `text-ink/ink-2/ink-3`, 선 `border-line(-strong)`.
  - `bg-accent`(나무 갈색 #573c2d): 만들기·저장 버튼, 내가 보낸 메시지, 강조 글자에 쓴다.
  - `bg-mark`(주황 #fe804d): 오늘, 선택 탭 밑줄, 안 읽음 점·배지, 로고 띠에만 쓴다. **글자색으로 쓰지 않는다.**
  - `bg-accent-soft`: 선택 바탕.
- **글꼴**
  - 제목·날짜 머리·항목 제목·선택 탭·로고는 `font-display`(Jua)다. `next/font/google` 로 빌드 때 받아 자체 호스팅하므로 CSP 를 바꾸지 않아도 된다. 빌드에는 네트워크가 필요하다.
  - 본문은 Pretendard(jsDelivr), 숫자·시각은 `.stamp`(Pretendard Medium 고정폭)다. 주아에는 굵기를 주지 않는다.
- **컴포넌트**
  - 버튼은 `.btn-primary/secondary/ghost/danger`(높이 36), `.btn-sm`, `.btn-icon`. 그 밖에 `.form-input`(흰 바탕 + 실선), `.card`, `.chip`.
  - 공통 부품은 `components/ui.tsx` 에 있다: `PageHeader`, `Ribbon`, `Dot`, `UnderlineTabs`, `Segmented`, `EmptyState`, `Modal`, `SideLabel`, `SideItem`. 새 화면도 이것을 쓴다.
- **규칙**
  - 모임 색(`lib/constants.ts` 의 `THEME_COLORS`, `getThemeColors(theme).hex`)은 띠·점으로만 쓴다. 배경을 칠하지 않는다.
  - 만들기 버튼은 화면 머리 오른쪽에 하나만 두고, FAB 는 쓰지 않는다.
  - 상단 메뉴는 6칸이다. 설정은 프로필 메뉴에 있다.
  - 모바일 하단 탭은 5칸이다. 메시지·알림은 위쪽 아이콘이다.
  - Tailwind 기본색(indigo/gray 등), `font-bold` 이상, `uppercase`, `transition-all`, 그라데이션, 이모지는 쓰지 않는다. 라이트 모드 전용이다.
- **되돌리기**: 배포 직전 운영 프론트 이미지를 `moyeolog-frontend:before-ui-20261124` 로 남겨 뒀다.

## 2차 QA 와 수정 (2026-11-22)

- QA: 운영과 같은 이미지의 격리 스택(`/home/ruraeru/moyeolog-qa/`, compose 프로젝트 `moyeolog-qa`, 127.0.0.1:3093/3094/8093)에서 에이전트 12개가 567건 실행 → 실패 191건. 결과 JSON `results/`, Figma QA 시트 2차 프레임. 스택은 배포 뒤 내렸다(`docker compose down`, 볼륨 유지). 다시 쓰려면 그 폴더에서 `docker compose up -d`.
- 수정: 에이전트 12개가 영역별 worktree(`/home/ruraeru/moyeolog-fix/`)에서 고치고, 세 레포의 `fix/qa2` 브랜치로 합쳤다. API 계약은 `/home/ruraeru/moyeolog-fix/CONTRACTS.md`.
- 재검증: 실패 191건 전부 재실행 → 실패 0(Kakao 로그인·지도·localhost 이미지 최적화 보류 11). 결과 `results-r2/`.
- 새 기능: 알림(종류별 설정), 친구 1:1 메시지, 다른 사용자 프로필, 도움말, 설정 4개 메뉴(알림·계정 및 보안·화면·언어 및 지역), 일정 주·목록 보기·종료 시각, 댓글 수정, 모임 나가기·삭제·초대 모달·초대 링크 확인 화면.
- 배포(2026-11-23): PR BE #3, FE #5, DEPLOY #6 머지 후 운영 반영. 직전 백업 `data/backup/db-20261123-051450.sql.gz`·`uploads-20261123-051450.tar.gz`. 실제 Kakao 로그인으로 운영 동작 확인.
- 배포 순서(이대로 했다): ① `backup.sh` ② 기존 앱 중지 ③ `migrations/2026-11-22-qa2/pre-deploy.sql` ④ `docker compose up -d --build`(포트 바인딩이 바뀌어 nginx·app 재생성 필요) ⑤ `post-deploy.sql` ⑥ 로그에서 `[topic-image-migration]` 확인 ⑦ crontab 등록.
- 운영 서버 메모리(11GB)가 작다: 에이전트·Playwright 를 12개 동시에 돌리면 서버가 다운된다(2026-11-22). 6개 이하로, 브라우저는 동시 2개 이하로.

## 남은 일

- 고치지 않은 것: customId 변경 기능, robots/OG 태그, 앱 전체 영어 번역('언어 및 지역'은 12/24시간 표시만), CSP 의 `'unsafe-eval'`(Kakao 지도 SDK 가 필요한지 확인 못 함).
- 알고 있는 한계: 친구 삭제와 메모 공유가 동시에 오면, 또는 같은 초대를 동시에 두 번 보내면 409(다시 시도하면 됨). `/memo` 는 모임마다 요청을 하나씩 보내 모임이 아주 많으면 rate limit 에 가깝다. 폴링 주기 메시지 5초·토픽 10초·모임 화면 15초·배지 30초. 댓글 멘션을 고른 뒤 입력창으로 포커스가 돌아가지 않는다.
- 확인하지 못한 것: 3003 포트가 외부 인터넷에서 직접 닿는지(8083 은 127.0.0.1 전용이라 LAN 에서도 안 닿는 것 확인).
- 대화에 평문으로 올라온 키(Gemini, Kakao Client Secret, Kakao 어드민 키)는 재발급 권장.

## 시연 영상 (2차 완성, 2026-11-12)

제출용 시연 영상. 자막만 있고 음성은 없다. 실제 계정으로 찍었다: 주인공 황태우, 상대역 박재선.

- 결과: `/home/ruraeru/moyeolog-demo/moyeolog-demo.mp4` (4:16, 1920×1080 H.264). 0:20, 0:43 의 이메일 노출 1프레임은 결과 파일에 ffmpeg 블러로 덧씌웠다(`edit.js` 를 다시 돌리면 빠진다. 다음 녹화부터는 `record.js` 가 MutationObserver 로 즉시 가린다)
- 작업 폴더 `/home/ruraeru/moyeolog-demo/` (레포 밖), 실행은 `./run.sh node scripts/<파일>` (도구 컨테이너 `moyeolog-demo-tools`)
  - `make-sessions.js`: 백엔드 sync 로 NextAuth 세션 쿠키 생성 → `state/*.json`. 토큰 24시간, 다시 찍기 전에 재실행
  - `seed-demo.js`: 황태우 예시 메모 3·일정 2, 황태우↔동주 친구 (넣음)
  - `prep-record.js`: 황태우 원래 프로필 백업(`state/taewoo-profile-backup.json`), 김수민→황태우 대기 요청 삭제
  - `record.js`: 세 브라우저(로그아웃·황태우·김수민)를 동시에 녹화, `raw/run/timeline.json` 에 화면 전환·자막·잘라낼 구간 기록. 실서비스에 실제로 쓴다(메모·모임·일정·토픽·댓글, Gemini 2회)
  - `edit.js`: timeline + 영상 → mp4. 자막은 ASS 로 입힌다
  - `cleanup-run.js`: 마지막 녹화가 만든 메모·일정·토픽·모임과 황태우↔김수민 친구 관계 삭제 (재촬영 전에 실행)
  - 메모: `notes/` (에이전트가 정리한 장면별 선택자·이메일 위치·자막 초안)
- 주의: Playwright 녹화 영상은 실제 시간과 어긋난다(1차 시도에서 끝 무렵 16초). 그래서 `record.js` 가 화면 오른쪽 아래 96×6px 에 타임코드를 그리고, `edit.js` 가 이를 읽어 맞춘 뒤 잘라낸다. 이메일은 녹화 브라우저 안에서 CSS 블러로 가린다. 긴 입력은 `fast`/`slow` 이벤트로 표시해 편집에서 2배속. 녹화 중에 다른 무거운 작업(ffmpeg 등)을 돌리면 화면이 느려져 영상이 길어진다(5:27 로 늘어난 적 있음).
- 녹화로 바뀐 실데이터: 황태우 프로필 사진·자기소개(백업 있음), 황태우↔박재선 친구, 메모 "팀 프로젝트 중간발표 준비 회의"(박재선에게 공유), 모임 "팀 프로젝트 모임"(초대 코드가 영상에 나옴), 일정 11/18 19:00, 토픽·댓글. 제출 뒤 정리 여부는 사용자에게 물어볼 것.
- 2차 촬영 전에 사용자 요청으로 DB 내용(메모·일정·모임·친구·토픽)을 전부 지우고(계정 4개는 유지) `seed-demo.js` 로 깔끔한 예시 데이터를 넣었다. 지우기 전 덤프: `data/backup/before-demo-wipe-20261112-091254.sql`.
