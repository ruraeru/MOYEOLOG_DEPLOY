# MOYEOLOG 배포 레포

메모·일정·모임·친구 서비스 MOYEOLOG의 Docker 배포 구성. 프론트(Next.js)와 백엔드(Spring Boot)는 서브모듈이다.

- 운영 주소: https://moyeolog.ruraeru.xyz
- 서브모듈: `MOYEOLOG_FE` (github.com/ruraeru/MOYEOLOG_FE), `MOYEOLOG_BE` (github.com/ruraeru/MOYEOLOG_BE)
- 브랜치: 세 레포 모두 `main`. `fix/qa-findings`(2026-11-12), FE `design/unslop`(2026-11-14), `fix/qa2`(2026-11-23), FE `design/unslop-2`(2026-11-24), FE·BE `feat/group-identity`(2026-11-24), `feat/email-auth`·FE `feat/login-fold`(2026-11-25), `feat/weather`(2026-11-25), FE 로고(`feat/logo-s6`·`feat/logo-s11`·`feat/logo-s11-mark`)·`fix/login-landing-home`(2026-11-25), FE·BE `feat/midpoint`(2026-11-25) 는 PR 로 머지했다(merge commit). 머지된 브랜치는 2026-11-25 에 로컬·원격 모두 지웠고 `main` 만 남아 있다(커밋은 `main` 의 머지 커밋에 있다). `/home/ruraeru/moyeolog-fix/` 의 worktree 는 브랜치 없이 같은 커밋에 남겨 뒀다(QA 덧붙이기 파일이 빌드 원본으로 쓴다). 실서비스는 `main` 과 같은 코드로 돌고 있다.

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
- 호스트에 JDK 가 없다. node 는 Claude Code 플러그인 훅용으로 `~/.local/opt` 에 22 가 있을 뿐이다(2026-11-24). 검증은 Docker 로 한다.
  - 백엔드 테스트: `docker run --rm -v "$PWD":/src -w /src eclipse-temurin:25-jdk-alpine ./gradlew test --no-daemon` (H2 사용, 197개)
  - 프론트 타입 검사: `node:20-alpine` 컨테이너에서 `npm ci && npx tsc --noEmit`
- DB 접속: `docker exec moyeolog-db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" moyeolog'`
- 백업: `backup.sh` (DB + 업로드 볼륨 → `data/backup/`, 14일 보존, 권한 600). 매일 04:00 crontab 으로 돈다(2026-11-23 등록, 로그 `data/backup/backup.log`). 수동 덤프도 `data/backup/` (gitignore 대상).

## 꼭 알아야 할 것

- **백엔드에 `application.yml` 이 없다** (gitignore). 운영 설정은 전부 `docker-compose.yml` 의 환경변수로 들어간다. 새 프로퍼티는 `@Value` 기본값을 주고 `application.yml.example` 과 compose 에 추가한다.
- **`INTERNAL_API_SECRET`**: 프론트 서버(NextAuth)가 백엔드 `POST /api/auth/sync`·`POST /api/auth/logout` 을 부를 때 `X-Internal-Secret` 헤더로 보낸다(이메일 로그인 `POST /api/auth/login`, 카카오 연결 `POST /api/auth/link-kakao` 도 같다). 프론트·백엔드 컨테이너에 같은 값이 있어야 로그인이 된다. nginx 는 `/api/auth/sync`, `/api/auth/refresh`, `/api/auth/logout`, `/api/auth/login`, `/api/auth/link-kakao` 를 외부에 404 로 막는다.
- **로그인 방법**: 카카오와 이메일+비밀번호 두 가지다(자세한 규칙은 아래 '이메일 가입 + 카카오 연동'). 카카오 로그인은 kakaoId 로 찾는다. 못 찾으면 Kakao 가 '검증됨'으로 넘긴 이메일이고, 그 이메일의 계정이 정확히 하나이며 아직 한 번도 카카오에 연결되지 않았을 때(`users.kakao_linked_at IS NULL`)만 그 계정에 붙인다. 이메일로만 가입한 계정(`kakao_id IS NULL`)은 그 이메일이 인증돼 있어야 붙는다. 카카오를 해제한 계정은 `kakao_linked_at` 이 남아 다시 자동으로 붙지 않는다. 그 밖에는 새 계정.
- **토큰**: 로그아웃하면 그 기기의 리프레시 토큰을 지우고 액세스 토큰 jti 를 만료까지 거부한다(`revoked_access_tokens`). '모든 기기 로그아웃'은 `users.tokens_valid_after` 이전 토큰을 거부. `exp` 없는 토큰·typ 없는 예전 토큰은 거부(`JWT_ACCEPT_LEGACY_TOKENS` 기본 false).
- **시간**: 일정 시각과 작성 시각은 오프셋 없는 한국 시간 `LocalDateTime` 이다. 백엔드 컨테이너는 `TZ=Asia/Seoul`. 프론트는 `yyyy-MM-dd'T'HH:mm:ss` 로 보낸다 (`toISOString()` 금지).
- **스키마**: `ddl-auto=update`. Hibernate 는 기존 컬럼 타입을 바꾸지 않으므로 타입 변경은 직접 `ALTER TABLE` 해야 한다.
- **nginx `add_header`**: location 안에 `add_header` 가 하나라도 있으면 server 레벨 헤더가 전부 빠진다. 그런 location 에는 `include /etc/nginx/snippets/security-headers.conf;` 를 넣는다.
- **nginx snippets**: `proxy.conf`(공통 프록시 헤더 + 백엔드·프론트가 보내는 보안 헤더 숨김 → 중복 없이 nginx 것 하나만), `json-errors.conf`(nginx 가 만드는 413·429 를 JSON 으로). 본문 한도는 10m(백엔드와 같음) — 넘으면 바로 JSON 413. `/_next/image` 에도 별도 rate limit.
- **신뢰 프록시**: `set_real_ip_from 172.30.1.10` (Caddy) 하나만 신뢰한다. Caddy 주소가 바뀌면 nginx 접속 로그의 `peer=` 값을 보고 고친다. 범위를 넓히면 `X-Forwarded-For` 조작으로 rate limit 이 우회된다.
- **CSP**: `nginx/conf.d/default.conf` 에 있다. Kakao 지도 SDK 는 `*.kakaocdn.net` 에서 스크립트를 받는다. 외부 리소스를 추가하면 CSP 도 고친다.
- **업로드**: 백엔드가 파일 내용(매직 바이트)으로 JPEG/PNG/GIF/WEBP 만 받고 확장자는 서버가 정한다. nginx 는 `/uploads/` 에서 이미지 확장자만 이미지로 내려주고 나머지는 다운로드로 처리한다. 업로드 볼륨은 uid 1001 소유여야 한다 (백엔드가 non-root 로 실행).
- **알림·메시지**: 백엔드 `notification/`, `message/` 패키지. 다른 서비스는 `event/NotificationEvent` 를 발행만 하고, 리스너가 커밋 뒤 받는 사람 설정을 확인해 저장한다. 메시지는 친구끼리 1:1, 프론트는 5초(대화)·30초(배지) 폴링.
- **대화 지우기**(BE #10, FE #24, 2026-11-25): 메시지 목록의 대화 줄마다 휴지통 버튼이 있다. `DELETE /api/messages/{friendId}` 는 지금까지의 메시지를 요청한 사람 쪽에서만 숨긴다(`messages.hidden_by_sender`·`hidden_by_recipient`). 상대에게는 남고, 그 뒤에 온 메시지는 다시 보인다. 안 읽은 것은 읽음으로 돌리고, 두 사람이 모두 지운 메시지는 행을 없앤다. 메시지를 조회하는 쿼리를 새로 쓸 때는 이 두 칸을 걸러야 한다(`MessageRepository.BETWEEN`). 되돌리기 이미지 `moyeolog-{app,frontend}:before-msgdel-20261125`.
- **실시간 갱신**: 변경 API 는 `event/ChangeEvent` 를 발행하고 화면은 SSE 토픽을 구독한다(아래 '실시간 갱신'). 폴링은 SSE 가 끊겼을 때의 안전망이다.
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
  - `bg-mark`(주황 #fe804d): 오늘, 선택 탭 밑줄, 안 읽음 점·배지, 로고의 ㅇ 에만 쓴다. **글자색으로 쓰지 않는다.**
  - `bg-accent-soft`: 선택 바탕.
- **글꼴**
  - 제목·날짜 머리·항목 제목·선택 탭은 `font-display`(Jua)다(로고는 글꼴이 아니라 SVG). `next/font/google` 로 빌드 때 받아 자체 호스팅하므로 CSP 를 바꾸지 않아도 된다. 빌드에는 네트워크가 필요하다.
  - 본문은 Pretendard(jsDelivr), 숫자·시각은 `.stamp`(Pretendard Medium 고정폭)다. 주아에는 굵기를 주지 않는다.
- **컴포넌트**
  - 창(`Modal`)의 겹침 순서는 기본 `z-[110]` 이다. 모바일 하단 탭이 `z-[100]` 이므로 `zIndex` 를 100 아래로 주면 화면 아래에 붙는 버튼 줄이 하단 탭에 가려진다(새 모임 만들기 창이 `z-50` 이라 '모임 만들기' 버튼이 안 보였다. FE #28, 2026-11-25 수정·배포, 되돌리기 이미지 `moyeolog-frontend:before-gcz-20261125`). 다른 창 위에 뜨는 창만 더 높은 값(`z-[120]`)을 준다.
  - 모바일 입력칸 글자는 16px 다. iOS Safari 는 16px 보다 작은 입력칸에 포커스가 가면 화면을 확대하므로, `globals.css` 맨 아래에서 터치 기기(`pointer: coarse`)의 `input`·`textarea`·`select` 를 16px 로 올린다(데스크톱은 `.form-input` 의 14px 그대로, 손가락 확대는 막지 않는다). 마크다운 편집기는 입력칸과 색칠용 글자가 겹쳐 있어 둘을 같이 16px/22px 로 맞춘다. 모바일에서 좁은 칸에 입력칸을 나란히 둘 때는 16px 기준으로 폭을 잡는다(일정 창의 날짜·시간 칸). FE #32, 2026-11-25 배포, 되돌리기 이미지 `moyeolog-frontend:before-inputzoom-20261125`. 실제 아이폰에서는 확인하지 못했다.
  - 버튼은 `.btn-primary/secondary/ghost/danger`(높이 36), `.btn-sm`, `.btn-icon`. 그 밖에 `.form-input`(흰 바탕 + 실선), `.card`, `.chip`.
  - 공통 부품은 `components/ui.tsx` 에 있다: `PageHeader`, `Ribbon`, `Dot`, `UnderlineTabs`, `Segmented`, `EmptyState`, `Modal`, `SideLabel`, `SideItem`. 새 화면도 이것을 쓴다.
- **로고** (FE PR #10·#11·#13, 2026-11-25): `components/Logo.tsx` 한 SVG 다. 옅은 주황 타일의 2×2 초성(ㅁㅇㄹㄱ) + 가로 한 줄 "모여로그". 굵은 한 줄 선(`text-accent`)이고 ㅇ 만 주황 점(`--mark`)이다. 이름이 그림 안에 있어 글자를 따로 붙이지 않는다. `height` 는 타일 높이(상단 메뉴 30·32px, 로그인·가입 46px). 탭 아이콘은 같은 2×2 를 `app/icon.svg` 로 쓴다(기본 `favicon.ico` 는 지웠다). 시안은 Figma 페이지 "서비스 로고 시안 (2026-11-24)" 의 S11(1~7차 시안이 모두 남아 있다). 되돌리기 이미지 `moyeolog-frontend:before-logo-20261125`.
- **로그인 뒤 첫 화면**은 홈이다(FE PR #12): `lib/url-safety.ts` 의 `safeCallbackPath` 기본 경로 `/home`. `callbackUrl` 이 있으면 그 경로.
- **로그인 화면 문구**(FE PR #29, 2026-11-25): 큰 제목 "모임장도 모임원도, / 모이기 쉽게 잊지 않게", 작은 설명 "장소 정하기부터 함께 보는 일정과 메모까지, 모임의 모든 일을 한곳에서 해결해요". 사이트 설명(`layout.tsx` metadata, `manifest.ts`)도 같은 작은 설명이다. 문구를 바꾸면 세 곳을 같이 고친다.
- **모임 일정의 '전체' 멘션**(FE PR #30·#31, 2026-11-25): 모임을 고른 일정 모달(`AppointmentModal`)에서 참여자 칸에 `@` 를 치면 목록 맨 위에 '전체 (N명)' 이 나온다(`@전`, `@전체` 도). 고르면 아직 안 고른 모임 멤버가 한 번에 참여자로 들어간다. 아직 안 고른 멤버가 없거나 개인 일정이면 나오지 않는다(둘뿐인 모임에서도 나오게 FE #31 에서 고쳤다). 프론트만 바꿨다.
- **모임 얼굴** (FE PR #7, BE PR #4, 2026-11-24): 모임 수정에서 바꾼 사진·색이 화면에 보이게 했다
  - `components/groups/GroupIdentity.tsx`: `GroupCover`(배경 사진 표지, 없으면 모임 색 옅은 줄무늬), `GroupAvatar`(프로필 사진, 둥근 사각형, 없으면 모임 색 바탕 + 첫 글자), `groupStyle(theme)`.
  - 모임 화면 루트에 `style={groupStyle(group.colorTheme)}` 를 깔면 그 안에서 `bg-group`(모임 색), `text-group-ink`(글자용 진한 톤), `bg-group-wash`/`bg-group-soft`(옅은 바탕), `text-group-sel`(선택 글자)이 모임 색이 된다. 루트 밖에서는 기본색(주황·갈색·raised·ink)으로 돌아간다. 모임 달력은 `.group-cal`(globals.css).
  - 사진 지우기: `PUT /api/groups/{id}` 의 `group` JSON 에 `removeProfileImage`·`removeBackgroundImage`. 새 파일이 오면 새 파일이 이긴다.
- **규칙**
  - 모임 색(`lib/constants.ts` 의 `THEME_COLORS`, `hex`·`ink`)은 모임 화면 안에서는 표시(탭 밑줄, 띠, 오늘·선택, 태그 선택, 표지)에 쓴다. 카드·페이지 전체를 칠하지 않고, 모임 색 위에 흰 글자를 올리지 않는다(노랑·하늘색 대비 부족). 모임 밖 화면에서는 띠·점 + 작은 `GroupAvatar` 로 구분한다.
  - 만들기 버튼은 화면 머리 오른쪽에 하나만 두고, FAB 는 쓰지 않는다.
  - 상단 메뉴는 6칸이다. 설정은 프로필 메뉴에 있다.
  - 모바일 하단 탭은 5칸이다. 메시지·알림은 위쪽 아이콘이다.
  - Tailwind 기본색(indigo/gray 등), `font-bold` 이상, `uppercase`, `transition-all`, 그라데이션, 이모지는 쓰지 않는다. 라이트 모드 전용이다.
- **되돌리기**: 배포 직전 운영 프론트 이미지를 `moyeolog-frontend:before-ui-20261124` 로 남겨 뒀다. 모임 얼굴 배포 직전 이미지는 `moyeolog-{frontend,app}:before-gi-20261124`, 백업 `data/backup/db-20261124-131227.sql.gz`.

## 이메일 가입 + 카카오 연동 (feat/email-auth, 2026-11-25 운영 배포)

계정 하나에 로그인 방법 두 개(이메일+비밀번호, 카카오)가 붙는다. 계정 두 개를 합치는 기능은 없다.

- **경로**: nginx 가 `/api/auth/*` 를 프론트(NextAuth)로 보내므로, 브라우저가 부르는 백엔드 API 는 `/api/account/**`(공개: 가입·인증·비밀번호 찾기)와 `/api/users/me/{password,email,kakao}` 다. 백엔드 `/api/auth/login`·`/api/auth/link-kakao` 는 프론트 서버만 부른다(`X-Internal-Secret`, nginx 404).
- **가입**: `POST /api/account/signup` → 인증 메일(`/verify?token=…&purpose=signup`) → `/verify` 에서 가입 때 정한 비밀번호를 다시 넣어야 계정이 생긴다(남의 이메일로 신청해 두는 선점 방지). 응답은 계정 유무와 관계없이 202.
- **이메일 인증 여부** `users.email_verified_at`: 인증 메일 또는 카카오의 '인증됨'으로만 채운다. 미인증 이메일은 '사용 중'으로 치지 않고, 누가 인증으로 확정하면 다른 미인증 계정의 같은 이메일은 NULL 이 된다(`AuthService.claimVerifiedEmail`). sync 는 카카오가 미인증으로 준 이메일을 저장하지 않는다.
- **자동 연결**: 카카오 로그인 때 kakaoId 로 못 찾으면, 카카오가 인증한 이메일과 정확히 같은(Java `equals`, DB 콜레이션은 악센트를 무시하므로) 인증된 이메일 가입 계정에 붙인다. 이메일이 다르면 설정 → 카카오 연결(`POST /api/auth/link-intent` 쿠키 5분 → 카카오 콜백에서 `link-kakao`). 연결 모드가 어긋나면 로그인으로 넘어가지 않고 `linkError=LinkFailed`.
- **기존 카카오 사용자**: 배포 직후 `email_verified_at` 이 NULL 이다. 카카오로 한 번 로그인하면 채워진다. 그 전에 같은 이메일로 가입·비밀번호 찾기를 하면 '카카오로 로그인하세요' 안내 메일만 간다.
- **재인증**: 비밀번호가 있으면 이메일 변경·카카오 해제·비밀번호 변경에 현재 비밀번호가 필요하다. 비밀번호가 없는 카카오 계정은 `users.last_kakao_login_at` 이 10분 안이어야 첫 비밀번호 설정·이메일 등록이 된다(아니면 403 + '카카오로 다시 로그인' 버튼). 비밀번호 변경·재설정은 모든 기기 로그아웃.
- **잠금**: 같은 (이메일, IP) 10회 실패 → 그 조합 10분 차단(앱 메모리). 계정 단위는 연속 100회 → 10분. 응답은 전부 같은 401. IP 는 nginx 의 `X-Real-IP` 를 프론트 서버가 `clientIp` 로 넘긴다.
- **메일**: `SPRING_MAIL_*`, `MAIL_FROM`, `APP_URL`. `SPRING_MAIL_HOST` 가 비면 메일이 필요한 요청은 503. 발송은 커밋 뒤 별도 스레드. 상한(앱 메모리): 이메일별 1분 1통·1시간 5통, 전체 시간당 200통(보안 알림은 제외), 이메일 등록은 사용자별 하루 5통.
- **nginx**: `account_limit`(분당 10, `/api/account/` 와 `/api/users/me/{password,email,kakao}`), `credentials_limit`(분당 20, `/api/auth/callback/credentials`).
- **배포 순서**: ① `backup.sh` ② `migrations/2026-11-25-email-auth/pre-deploy.sql`(`kakao_id` NULL 허용. 새 컬럼·`email_verifications` 는 Hibernate 가 만든다) ③ `.env` 에 SMTP 값 ④ `docker compose up -d --build` ⑤ nginx reload ⑥ 실제 카카오로 로그인·연결·409 확인(QA 에서 실제 OAuth 는 못 돌렸다).
- **배포(2026-11-25)**: PR BE #5, FE #8·#9(로그인 화면의 이메일 폼을 '이메일로 계속하기' 버튼 뒤로 접음), DEPLOY #12·#13 머지 후 운영 반영. 직전 백업 `data/backup/db-20261125-080616.sql.gz`·`uploads-20261125-080616.tar.gz`, 되돌리기용 이미지 `moyeolog-{app,frontend}:before-ea-20261125`. SMTP 는 Gmail(앱 비밀번호, `.env`). 발송은 SMTP 단계까지 확인했고, 실제 카카오 로그인·연결은 아직 확인하지 않았다.
- **작업물**: worktree `/home/ruraeru/moyeolog-fix/ea-{be,fe,deploy}`, 계약 `EA_BRIEF.md`·`EA_FIX.md`, 보고서 `ea-report/`(리뷰 `review.md`·`review2.md`, QA `qa3.md`). QA 는 `/home/ruraeru/moyeolog-qa` 에서 `docker-compose.ea.yml`(mailpit 127.0.0.1:8025).
- **알고 있는 한계**: 응답 시간으로 계정 유무를 추측할 여지(측정 안 함). 여러 IP 로 계정 잠금(100회)을 걸 수 있음(비밀번호 찾기로 풀림). 가입 요청으로 시간당 200통 상한을 채우면 그동안 가입·재설정 메일이 버려짐. 비밀번호 변경·재설정과 같은 초에 한 로그인은 받은 토큰이 바로 401(`tokens_valid_after` 가 초 단위). 카카오를 해제한 뒤 그 카카오로 시작하면 빈 새 계정이 생김.

## 날씨 (feat/weather, 2026-11-25 운영 배포)

일정에 약속 장소를 지도에서 고르면 그 장소의 예보를 보여 주고, 날씨에 맞춰 주변 추천 순서를 바꾼다. '내 지역' 설정은 없다. 날씨는 항상 일정의 장소 기준이다.

- **출처**: 기상청 API허브(apihub.kma.go.kr)의 단기예보(`VilageFcstInfoService_2.0/getVilageFcst`, 격자·시간별 3~4일)와 중기예보(`MidFcstInfoService/getMidLandFcst`·`getMidTa`, 지역·일별 10일까지). 키는 `KMA_SERVICE_KEY`(쿼리 `authKey`). data.go.kr 키가 아니다. API허브 활용신청은 조회 항목 단위다: `getVilageFcst`, `getMidLandFcst`, `getMidTa` 세 개를 신청했다(2026-11-25). 신청하지 않은 항목은 403.
- **백엔드** `weather/`: `GET /api/weather?lat=&lng=` → `{hourly:[{time,sky,temp,pop}], daily:[{date,sky,pop,min,max}]}`. `sky` 는 `CLEAR·PARTLY·CLOUDY·RAIN·SLEET·SNOW`. 같은 날짜는 단기가 중기를 덮는다. 격자·지역별로 다음 발표 시각까지 메모리 캐시. 중기예보는 하루치만 보관되므로 새 발표(06·18시)가 아직 없으면 직전 발표를 쓴다. 단기 응답의 마지막 날은 자정 한 시각뿐이라 일별 요약을 만들지 않는다. 한쪽만 실패하면 남은 쪽만 주고, 둘 다 실패하거나 키가 없으면 503(화면은 날씨만 숨김). 국외 좌표는 400.
- **중기 지역**: 가장 가까운 대표 도시 28곳(`MidRegion`)의 값을 쓴다. 코드는 API허브 예보구역 목록으로 확인했다.
- **좌표**: `schedules.latitude`·`longitude`(NULL 허용, Hibernate 가 만든다). 지도에서 장소를 골랐을 때만 저장하고, 장소 글자를 직접 고치면 지운다. 예전 일정은 좌표가 없어 달력·홈에 날씨가 안 나온다(상세 화면은 장소 검색 결과 좌표로 대신한다).
- **프론트**: `lib/weather.ts`(조회, `weatherAt`, 추천 규칙 `recommendFor`), `hooks/useWeather.ts`(`usePlaceWeather`, `useScheduleWeather` — 한 화면 장소 8곳까지), `components/Weather.tsx`(`WeatherIcon`, `WeatherLine`). 달력(월·주)·모임 달력은 날짜 칸 오른쪽 위 아이콘, 홈·일정 상세는 '비 7° · 강수 80%' 한 줄, 일정 모달은 날씨 + 추천.
- **아이콘 색** (`globals.css` 의 `--wx-*`, 클래스 `text-wx-sun/rain/snow`, FE #17·#18): 맑음·구름 많음은 노랑 `#f59f00`, 비·비 또는 눈은 파랑 `#1c7ed6`, 눈은 청록 `#0cb0c9`, 흐림은 `ink-3`. 16px, 선 굵기 2, 같은 색 22% 채움(`Weather.tsx` 의 `SHAPE`). 눈에 띄는 쪽을 골라서 노랑은 흰 바탕 대비가 3:1 에 못 미친다. 아이콘에만 쓰고 글자에는 쓰지 않는다.
- **추천 규칙**: 비·눈 또는 강수확률 60% 이상, 33° 이상, -5° 이하 → 카페·문화시설·음식점. 맑음·구름 많음 → 관광명소·음식점·카페. 그 밖·예보 없음 → 음식점·카페. 종류마다 3곳씩 모두 5곳. 가짜 별점(`Math.random`)은 지웠다.
- **QA**: `/home/ruraeru/moyeolog-qa` 에서 `docker-compose.wx.yml`(ea 파일 뒤에 붙임, 가짜 기상청 `scripts/wx-kma-mock.js`), `./pw.sh node scripts/wx-ui.js` → 21건 통과, 스크린샷 `shots/wx/`. 실제 기상청은 `docker-compose.wx-real.yml` 을 더 붙이고 `./pw.sh node scripts/wx-real.js` 로 확인했다(2026-11-25, 서울·부산·제주·강릉 모두 200, 오늘부터 11일치, 첫 요청 약 2초·캐시 11ms). localhost 에서는 Kakao 지도가 안 떠서 일정 모달의 날씨·추천은 확인하지 못했다.
- **PR**: BE #7, FE #15 머지(2026-11-25). 배포 레포는 서브모듈 포인터를 두 머지 커밋으로 옮겼다.
- **배포**: 2026-11-25 중간 지점 기능과 함께 운영에 올렸다(`backup.sh` → 빌드 → nginx reload, 마이그레이션 SQL 없음). 운영에서 `/api/weather` 200 과 일정 모달의 날씨·추천은 아직 눈으로 확인하지 않았다.
- **아이콘 색 배포**(2026-11-25): 프론트만 두 번 다시 빌드했다(FE #17 → #18). 되돌리기 이미지 `moyeolog-frontend:before-wxcolor-20261125`(색 없음), `before-wxvivid-20261125`(첫 색). 백업 `data/backup/db-20261125-095637.sql.gz`. 운영 CSS 의 `--wx-*` 값으로 반영을 확인했고, 로그인한 화면은 눈으로 확인하지 않았다.

## 중간 지점 찾기 (feat/midpoint, 2026-11-25 운영 배포)

여럿이 만나는 일정에서 각자 출발지를 적으면 가운데에서 가까운 지하철역을 추천하고, 일정을 만든 사람이 하나를 골라 일정 장소로 정한다.

- **백엔드** `midpoint/`: 테이블 `schedule_departures`(일정·사용자별 한 줄, 이름 + 좌표, 일정 삭제 시 `ON DELETE CASCADE`, 회원 탈퇴 리스너). API 는 `/api/schedules/{id}/midpoint` 아래다.
  - `GET`: 적은 사람 목록(이름만), 내 출발지, 지난번 출발지(다른 일정에 마지막으로 적은 것), 가운데 좌표(2명 이상일 때, 좌표 평균), 적은 사람 수/대상 수.
  - `PUT /departure`·`DELETE /departure`: 내 출발지 저장·삭제.
  - `POST /request`: 아직 안 적은 사람에게 알림. `POST /confirm` `{name, latitude?, longitude?}`: 일정 장소(이름 + 좌표)로 저장하고 나머지에게 알림. 둘 다 일정을 만든 사람만.
- **권한**: 모임 일정은 모임 멤버, 개인 일정은 만든 사람과 참여자. 그 밖은 403. 다른 사람의 출발지 좌표는 내려주지 않는다.
- **알림**: 새 종류를 만들지 않고 `SCHEDULE_PARTICIPANT`('일정 참여' 설정)를 쓴다.
- **프론트**: `components/MidpointSection.tsx`, `lib/midpoint-api.ts`. 일정 상세(`AppointmentDetailView`)의 '중간 지점' 행이고 모임 일정·참여자가 있는 일정에서만 보인다. 지하철역은 Kakao 지도 SDK 카테고리 검색(`SW8`, 반경 5km → 없으면 20km, 거리순)으로 찾고 같은 역의 노선은 한 줄로 묶어 5곳까지 보여 준다. 15초 폴링. 화면에 지도는 없고 카카오맵 링크만 있다.
- **확인**: BE 통합 테스트 3개(`MidpointIntegrationTest`), FE `tsc`·`eslint`. 운영 배포 뒤 컨테이너 healthy·테이블 생성·로그 오류 0 까지 봤다. 로그인한 화면에서 실제 동작(지하철역 추천)은 아직 눈으로 확인하지 않았다.
- **혼자인 일정**(FE #16): 대상이 한 명뿐이면(`expectedCount <= 1`) '중간 지점' 행을 통째로 숨긴다.
- **달력의 붉은 칸**(BE #8·#9, FE #19·#20): `ScheduleResponse` 에 `departureNeeded`(내가 출발지를 안 적음)와 `placeNeeded`(내가 만든 일정인데 장소 미정)가 있다. 둘 다 여럿이 만나고, 장소가 비었고, 끝나지 않은 일정에서만 true 다. 일정 달력(월·주·목록)과 모임 달력에서 그 칸을 `bg-negative-soft text-negative` 로 칠하고 까닭('출발지 미입력'/'장소 미정')을 적는다(`lib/schedule-api.ts` 의 `scheduleAlert`). 끝난 일정·혼자인 일정은 칠하지 않는다.
- **정해진 역 근처 추천**(FE #21·#22·#23·#25): 장소가 정해지면 역 목록 아래에 그 역 근처 추천 장소 5곳을 일정 시작 시각의 날씨에 맞춰 보여 준다(날씨 기능의 `recommendFor`·`fetchRecommendations`·`usePlaceWeather` 를 그대로 쓴다). 일정을 만든 사람은 추천 장소도 '여기로 정하기'로 일정 장소(이름 + 좌표)로 정할 수 있다. 정한 뒤에도 추천 목록은 기준 역 그대로 두지만 기준 역을 저장하지는 않으므로, 화면을 새로 열면 정한 장소 주변으로 다시 찾는다. 장소가 역이 아닌 곳으로 정해져 있으면 지하철역 목록과 추천 장소 목록을 둘 다 접어 두고 각각 '펼치기' 버튼을 둔다.
- **참여자 추가 알림**: 일정에 장소가 비어 있으면 문구 끝에 '출발지를 입력해 주세요!' 가 붙는다.
- **배포할 때**: 배포 폴더의 서브모듈에 다른 작업의 커밋 전 변경이 있을 수 있다. 그럴 때는 깨끗한 `main` worktree 를 빌드 컨텍스트로 덮어쓴 compose 파일을 `-f` 로 더 붙여 빌드하고 `docker compose up -d --no-build` 로 올린다(2026-11-25 에 이렇게 했다).
- **알고 있는 한계**: 가운데는 좌표 평균이지 이동 시간 기준이 아니다. 두 명일 때는 가운데와 내 출발지로 상대 위치를 대략 짐작할 수 있다.
- **PR**: BE #6·#8·#9, FE #14·#16·#19·#20·#21·#22·#23·#25. 작업 worktree `/home/ruraeru/moyeolog-midpoint/{be,fe}`. 되돌리기 이미지 `moyeolog-{app,frontend}:before-midpoint-20261125`, 백업 `data/backup/db-20261125-093541.sql.gz`.

## 실시간 갱신 (SSE, feat/live-refresh, 2026-11-25 운영 배포)

다른 사람이 만든 변경(일정·메모·친구·모임·토픽·메시지·알림)이 새로고침 없이 1초 안에 뜬다. WebSocket 이 아니라 SSE 다(서버 → 브라우저 한 방향, Caddy → nginx → Spring 을 그대로 통과).

- **백엔드** `live/`: `GET /api/events`(`text/event-stream`, 기존 JWT). 연결 직후 `event: ready`, 변경 때 `event: changed` + `data: {"topics":[…]}`, 25초마다 `: ping`. 이벤트는 '무엇이 바뀌었는지'만 싣고 본문은 기존 조회 API 가 권한을 검사해 준다.
- **토픽**: `schedules`, `schedule:{id}`, `memos`, `friends`, `groups`, `group:{id}`, `messages`, `notifications`. `group:{id}` 는 그 모임 멤버(변경 전·후)에게만 보낸다. 모임 밖 공유받은 사람·참여자는 같은 이벤트에서 나머지 토픽만 받는다.
- **발행**: 서비스가 트랜잭션 안에서 `event/ChangeEvent` 를 내고 `live/LiveEventListener` 가 커밋 뒤에 보낸다. 받는 사람 계산은 `live/LiveAudience`(일정 = 작성자·참여자·모임 멤버, 메모 = 작성자·공유받은 사람·모임 멤버), 사람마다 토픽을 묶는 것은 `event/ChangeEvents`. **새 변경 API 를 추가하면 그 서비스에서 `ChangeEvent` 도 낸다.** 삭제·공유 해제·내보내기는 지우기 전에 받는 사람을 계산한다.
- **연결**: 메모리 등록부 `LiveHub`(앱 인스턴스가 하나라는 전제. 여러 대로 늘리면 인스턴스 간 전달이 필요하다). 사용자당 6개(넘으면 `event: evicted` 뒤 닫음), 수명 min(30분, 토큰 만료), 로그아웃·모든 기기 로그아웃·회원 탈퇴 때 닫는다. 보내기는 작업마다 가상 스레드에서 한다. 설정 `live.max-connections-per-user`·`max-age-ms`·`heartbeat-ms`(기본값으로 충분, 환경변수 없음).
- **`SecurityConfig`**: `DispatcherType.ASYNC` permitAll. 첫 요청에서 이미 인증했고, 이게 없으면 스트림이 끝날 때 401 이 난다.
- **프론트**: `lib/live.ts`(`fetch` 스트림 SSE 클라이언트. `EventSource` 는 Authorization 헤더를 못 보낸다), `components/LiveEvents.tsx`(탭이 보이는 동안 연결 하나, 다시 붙으면 전체를 한 번 새로 고침), `hooks/useVisiblePolling.ts`. 화면은 `useLiveTopics([...], 조용한 다시 불러오기)` 로 구독한다. **자동 갱신 함수는 로딩 표시를 띄우지 않고 실패해도 보던 목록을 둔다(`silent`).**
- **폴링은 안전망으로 남아 있다**: SSE 가 붙어 있으면 전부 60초, 끊기면 원래 주기(일정·친구·홈·모임 15초, 메모 30초, 메시지 5초, 토픽 탭 10초·토픽 상세 5초, 중간 지점 15초, 배지 30초). 재접속은 1초 → 최대 30초, `evicted` 를 받으면 5분 쉰다.
- **nginx**: `location = /api/events`(버퍼링·캐시·gzip 끔, `proxy_read_timeout 2100s`). 전용 `events_limit`(60r/m, burst 30)과 IP 당 동시 `events_conn` 30. 재접속이 `api_limit` 을 쓰지 않는다.
- **QA**: `/home/ruraeru/moyeolog-qa` 에서 `docker-compose.live.yml`(ea → wx → live 순서로 붙임). `./pw.sh node scripts/live-ui.js --restart`(화면, 14건: 반영 0.3~0.9초, 탭 숨김·복귀, 백엔드 재시작 뒤 재접속. 재시작은 `state/live-restart.flag` 가 생기면 바깥에서 `docker restart moyeolog-qa-app` 후 지운다), `scripts/live-wire.js`(스트림 직접 확인 7건: 모임 ID 누출 없음, 연결 상한). **열린 SSE 때문에 Playwright `networkidle` 은 오지 않는다. `domcontentloaded` + `/api/events` 응답 대기를 쓴다.**
- **PR**: BE #11, FE #26. 작업 worktree `/home/ruraeru/moyeolog-fix/live-{be,fe,deploy}`, 지시서·보고서 `LIVE_BRIEF.md`·`LIVE_REVIEW.md`·`LIVE_REPORT_{BE,FE}.md`(같은 폴더).
- **배포 순서**: ① `backup.sh` ② `docker compose up -d --build`(백엔드·프론트 같이) ③ `docker exec moyeolog-nginx nginx -t && docker exec moyeolog-nginx nginx -s reload`(**필수**: 새 location·limit zone) ④ 도메인에서 `curl -sN -H "Authorization: Bearer <토큰>" https://moyeolog.ruraeru.xyz/api/events` 로 `event:ready` 와 25초 `: ping` 확인(Caddy 경유 버퍼링). 마이그레이션·새 환경변수 없음.
- **배포(2026-11-25)**: BE #11, FE #26, DEPLOY #25 머지 후 백엔드·프론트를 같이 올리고 nginx reload 했다. 직전 백업 `data/backup/db-20261125-111235.sql.gz`·`uploads-20261125-111235.tar.gz`, 되돌리기 이미지 `moyeolog-{app,frontend}:before-live-20261125`(nginx 설정은 `location = /api/events` 를 남겨 둬도 옛 백엔드에서 404 일 뿐이다). 확인한 것: 컨테이너 정상, 도메인에서 토큰 없는 `/api/events` 401 JSON, 보안 헤더 유지. **확인하지 못한 것: 로그인한 실제 연결이 Caddy 를 거쳐 버퍼링 없이 오는지.** nginx 로그에서 `/api/events` 200 의 `rt=` 가 60초 안팎으로 반복되면 Caddy 가 버퍼링하는 것이다(프론트가 60초 무응답으로 끊고 다시 붙는 모양). 정상이면 탭을 숨기거나 30분이 될 때까지 이어진다.
- **알고 있는 한계**: 닉네임·프로필 사진, AI 분석 결과, 메모 변경으로 바뀌는 '일정에 연결된 메모', 대화 지우기(내 쪽만)는 실시간으로 가지 않는다. 일정 상세 모달·메모 상세는 열려 있는 동안 내용이 바로 바뀌지 않는다(목록은 바뀐다). 끊긴 동안의 이벤트는 다시 보내지 않고 재접속 뒤 전체 새로 고침으로 메운다. 한 IP 뒤에서 30탭을 넘으면 그 뒤 탭은 429 → 폴링으로 돈다.

## 홈 화면 웹앱 (feat/pwa, 2026-11-25 운영 배포)

아이폰에서 '홈 화면에 추가'하면 Safari 바로가기가 아니라 앱처럼(주소창·도구 막대 없이) 뜬다. 전에는 매니페스트·iOS 메타·PNG 아이콘이 하나도 없었다.

- `MOYEOLOG_FE/src/app/manifest.ts`(`display: standalone`, `start_url: /home`), `src/app/apple-icon.png`(180), `public/icons/icon-192·512·maskable-512.png`, `layout.tsx` 의 `appleWebApp`·`viewport.themeColor`. 서비스 워커는 없다(오프라인·푸시 없음).
- 아이콘은 `src/app/icon.svg` 에서 sharp 로 뽑았다. 로고를 바꾸면 PNG 4개도 다시 만든다. iOS 는 투명 모서리를 검게 칠하므로 apple-icon 과 maskable 은 바탕을 꽉 채운 정사각형이다.
- `viewport-fit=cover` 는 넣지 않았다. 넣으면 하단 탭(`pb-safe` 는 지금 정의가 없다)과 `100dvh` 높이 계산을 같이 고쳐야 한다.
- 홈 화면 아이콘은 추가할 때의 설정으로 굳는다. 바꾼 뒤에는 지우고 다시 추가해야 한다. 앱 모드는 Safari 와 쿠키가 따로다.
- PR FE #27. 되돌리기 이미지 `moyeolog-frontend:before-pwa-20261125`, 백업 `data/backup/db-20261125-112236.sql.gz`.
- **확인하지 못한 것**: 실제 아이폰에서의 모양, 앱 모드에서 카카오 로그인(다른 도메인에 갔다 돌아올 때 세션이 붙는지).

## 링크 미리보기 (Open Graph, feat/link-preview, 2026-11-25 운영 배포)

링크를 메신저·SNS 에 공유하면 사이트 정보가 미리보기로 뜬다. 초대 링크는 모임 이름·보낸 사람이 뜬다.

- **사이트 전체**: `MOYEOLOG_FE/src/lib/site-meta.ts`(`SITE_*`, `pageMeta()`), `layout.tsx` 의 `metadataBase`(= `NEXT_PUBLIC_API_URL`)와 og·twitter 메타. 이미지 `public/og.png`(1200×630, 로고 도형을 sharp 로 그린 것. 로고를 바꾸면 다시 만든다).
- **페이지가 `openGraph` 를 정의하면 layout 것을 통째로 덮어쓴다**(이미지·사이트 이름이 사라진다). 페이지에서도 `pageMeta()` 로 만든다.
- **초대 링크**: `/invite/group?code=`(제목 '○○ 모임에 초대받았어요', 설명 '방장 · 멤버 n명 · 소개'), `/invite/friend?code=`('○○님이 모여로그 친구로 초대했어요'). `app/invite/*/page.tsx` 는 서버 컴포넌트이고 `generateMetadata` 가 `lib/link-preview.ts` 로 이름을 가져온다. 화면은 `GroupInviteClient`·`FriendInviteClient`. 코드가 틀리거나 백엔드가 2초 안에 답하지 않으면 이름 없는 기본 문구. 초대 화면은 `noindex`.
- **백엔드** `GET /api/auth/link-preview?type=group|friend&code=`: 프론트 서버만 `X-Internal-Secret` 으로 부른다. 이름·소개·인원·방장 닉네임(친구는 닉네임)만 준다. `/api/auth/**` 는 nginx 가 프론트로 보내 외부에서 닿지 않는다(외부에서 부르면 NextAuth 의 400).
- **미들웨어**: `/invite/*` 는 로그인 강제 목록(`middleware.ts` 의 `matcher`)에 없다. 미리보기 수집기는 로그인하지 않아, 로그인 화면으로 넘기면 초대 정보를 읽지 못한다. 비로그인 사용자는 초대 화면이 직접 `/?callbackUrl=…` 로 보낸다. **미리보기가 필요한 공유 링크를 새로 만들면 그 경로도 matcher 에 넣지 않는다.**
- **공개 범위**: 초대 링크를 가진 사람은 로그인 없이 모임 이름·소개·인원·방장 닉네임(친구 링크는 닉네임)을 본다.
- **QA**: `./pw.sh node scripts/og-ui.js`(24건: 수집기처럼 쿠키 없이 메타 태그 확인, 이름의 태그·따옴표, 내부 API 차단, 비로그인·로그인 사용자의 초대 흐름).
- **배포(2026-11-25)**: BE #12, FE #33. 백엔드·프론트를 같이 올렸다. 백업 `data/backup/db-20261125-124238.sql.gz`, 되돌리기 이미지 `moyeolog-{app,frontend}:before-og-20261125`. 운영 도메인에서 사이트·모임 초대·친구 초대 메타가 나오는 것을 확인했다.
- **보강(FE #34, 2026-11-26 배포)**: layout 은 기본 `og:url` 을 주지 않는다(`pageMeta` 의 `path` 는 선택. 전에는 `/help` 등 모든 화면이 첫 화면 주소로 나갔다). `next.config.ts` 의 `htmlLimitedBots` 에 카카오톡·네이버·라인 등 수집기를 넣어 메타 태그가 항상 `<head>` 에 들어간다. 되돌리기 이미지 `moyeolog-frontend:before-ogroot-20261126`, 백업 `data/backup/db-20261126-003445.sql.gz`. 첫 화면 주소만 카카오톡 미리보기가 안 뜨던 것은 코드가 아니라 카카오톡에 저장된 예전 미리보기 때문이었다(`/?v2` 는 바로 떴다).
- **확인하지 못한 것·한계**: 실제 카카오톡·문자에서의 모양. 카카오톡은 미리보기를 저장해 두므로 이미 공유한 링크는 카카오 개발자 도구의 공유 디버거에서 캐시를 지워야 바뀐다. 모임 사진은 미리보기 이미지로 쓰지 않는다(업로드가 webp 인데 카카오톡의 webp 미리보기 지원을 확인하지 못했다). robots.txt·sitemap 은 없다.

## 메모 공유 권한 (feat/memo-share-perm, 2026-11-26 운영 배포)

- **규칙**: 개인 메모를 공유받은 사람은 기본 읽기 전용이다. 작성자가 '수정 가능'으로 공유한 친구만 고칠 수 있다. 개인 메모를 모임에 공유하면 멤버는 읽기만 한다. 모임에서 쓴 메모(`memos.group_id`)는 멤버 누구나 고친다(전과 같다).
- **친구 공유**: `POST /api/memos/{id}/share` `{friendIds, canEdit?}`(없으면 false). 이미 공유한 친구에게 다시 보내면 그 친구의 권한만 바뀐다(알림은 새 친구에게만). `memo_shares.can_edit`(NOT NULL DEFAULT 0, 기존 공유는 읽기 전용). 수정 가능한 친구는 내용·태그를 고치지만 삭제·재공유·남의 공유 해제·분석은 못 한다.
- **모임 공유**: `POST`·`DELETE /api/memos/{id}/group-share/{groupId}`. 작성자만, 개인 메모만, 작성자가 멤버인 모임에만. 테이블 `memo_group_shares`((memo_id, group_id) 유일). 모임 메모 목록(`getGroupMemos`)은 모임에서 쓴 메모 다음에 공유된 개인 메모를 준다(공유된 것은 `groupId` 가 null). 알림은 보내지 않는다.
- **정리**: 메모 삭제, 모임 삭제, 작성자가 모임을 나가거나 내보내질 때 모임 공유를 지운다. 멤버가 나가면 그 모임에 공유된 메모를 더 못 본다. 모임 공유를 해제해도 멤버의 즐겨찾기 행은 남는다(목록에서만 숨겨진다).
- **응답**: `MemoResponse.sharedGroupIds`, `sharedWith[].canEdit`(둘 다 작성자에게만). 실시간 `LiveAudience.addMemo` 는 공유한 모임의 멤버에게도 `memos`·`group:{gid}` 를 보낸다. **메모를 읽을 수 있는지 판단하는 코드를 새로 쓰면 모임 공유(`MemoGroupShareRepository`)도 같이 본다**(`MemoService.canRead`, `ScheduleService.canReadMemo`).
- **프론트**: `MemoShareModal`(새 공유와 공유 중인 사람마다 '수정 가능' 체크, '모임에 공유' 칸), `/memo` 목록의 내가 공유한 내 메모 오른쪽 위 '공유함' 칩(`lib/memo-api.ts` 의 `isSharedByMe`), 모임 화면 `MemoCard` 의 '공유된 메모'.
- **배포**: BE #15, FE #38. 구현은 opus 에이전트가 했다(보고서 `/home/ruraeru/moyeolog-fix/MEMOSHARE_REPORT.md`). 사용자 요청으로 테스트·타입 검사·QA 를 돌리지 않고 배포했다(이미지 빌드의 컴파일만 통과, 고친 테스트 코드는 실행하지 않음). 운영에서 앱 기동, `can_edit` 칸(기존 4행 모두 0)과 `memo_group_shares` 생성, 로그 오류 0 까지 봤다. 로그인한 화면, 새 권한의 실제 동작, 375px 공유 창은 확인하지 못했다. 백업 `data/backup/db-20261126-025248.sql.gz`, 되돌리기 이미지 `moyeolog-{app,frontend}:before-memoshare-20261126`(되돌려도 새 칸·테이블은 남는다. 옛 코드에는 영향 없다).

## 모임 날짜 조율 (feat/date-poll, 2026-11-26 운영 배포)

모임원이 가능한 날짜를 고르면 취합해 추천하고, 모임장이 하나를 정하면 모임 일정이 된다. 모임 화면의 '일정' 탭에 있다.

- **백엔드** `datepoll/`: 테이블 `date_polls`(조율), `date_poll_votes`((조율, 사용자, 날짜) 유일. 날짜가 NULL 인 줄은 '응답했지만 가능한 날 없음'). Hibernate 가 만든다. API 는 `/api/groups/{groupId}/date-polls` 아래다.
  - `GET /`, `GET /{id}`: 멤버. `POST /`(제목 + 기간, 오늘 이후·최대 31일), `POST /{id}/remind`, `POST /{id}/confirm`(`{date, startTime, endTime?}`), `DELETE /{id}`: 모임장만.
  - `PUT /{id}/votes` `{dates}`: 내 선택을 통째로 바꾼다(빈 배열 = 가능한 날 없음). `POST /{id}/recommend`: AI 추천.
- **집계는 코드가 한다**: 날짜별 인원·`best`(인원 많은 순, 같으면 이른 날, 3개까지). LLM 은 요약과 추천 이유만 쓴다(`GeminiService.generateJson`, `AiAnalysisSupport` 의 일반형 `run` — 트랜잭션 밖 호출, 같은 조율이 진행 중이면 409, 실패 502). LLM 이 준 날짜 중 후보 밖·가능한 사람 0명인 날은 버리고, 한자·가나가 섞인 문장은 기본 문구('○명 중 ○명 가능')로 바꾼다. 남는 추천이 없으면 `best` 로 채운다. 추천 뒤 누가 선택을 바꾸면 `stale`.
- **확정**: `ScheduleService.createSchedule` 로 모임 일정을 만든다(참여자 = 그 날 가능하다고 한 멤버, 끝 시각을 안 주면 1시간). 참여자는 일정 생성 알림만, 나머지 멤버는 확정 알림을 받는다. 조율을 지워도 일정은 남는다.
- **알림·실시간**: 알림 종류는 `SCHEDULE_PARTICIPANT`, 링크는 `/groups/{id}?tab=calendar`. 변경마다 모임 멤버에게 `group:{id}` 토픽.
- **정리**: 모임 삭제(`GroupService.deleteGroupInternal`), 멤버 나가기·내보내기, 회원 탈퇴 때 선택·조율을 지운다. 탈퇴한 사람이 만든 조율은 새 모임장에게 넘어간다.
- **프론트**: `lib/date-poll-api.ts`, `components/DatePollModal.tsx`(조율 창 + 만들기 창), `app/groups/[id]/page.tsx`. 달력 위에 진행 중 조율 카드와 모임장용 '날짜 조율' 버튼. 조율 창은 후보 기간 격자(인원이 많을수록 모임 색이 진해짐), '많이 되는 날' 칩, AI 추천, 모임장의 '이 날로 정하기'·응답 재촉·지우기.
- **모임 화면의 조용한 갱신**은 429 를 받아도 화면을 오류로 바꾸지 않고 1.5초 뒤 한 번 다시 불러온다(전에는 화면 전체가 오류로 바뀌었다).
- **nginx**: `location ~ ^/api/groups/[^/]+/date-polls/[^/]+/recommend$` 에 `proxy_read_timeout 300s`(분석 요청과 같음).
- **QA**: `./pw.sh node scripts/date-poll-ui.js`(61건: 권한, 만들기, 고르기, 다른 창 반영 0.2~0.45초, 실제 LLM 추천 2~5초, 확정 → 일정, 읽기 전용, 지우기, 모바일 375px 31칸).
- **배포(2026-11-26)**: 백엔드·프론트를 같이 올리고 nginx reload(새 location 때문에 필수). 마이그레이션·새 환경변수 없음. 백업 `data/backup/db-20261126-022558.sql.gz`, 되돌리기 이미지 `moyeolog-{app,frontend}:before-datepoll-20261126`. 운영에서 컨테이너 정상, 두 테이블 생성, 토큰 없는 요청 401, 앱 로그 오류 0 까지 봤고 로그인한 화면은 확인하지 못했다.
- **권한 변경(BE #14, FE #37, 2026-11-26 배포)**: 조율 만들기는 모임 멤버 누구나 한다. 재촉·날짜 정하기·지우기는 그 조율을 만든 사람 또는 방장만(응답의 `canManage`). 위 API 목록의 '모임장만'은 이 규칙으로 읽는다. 알림 문구의 이름은 실제로 행동한 사람이다. 격자 칸 날짜는 모든 칸이 월/일(`11/27`)이다. 만든 사람이 모임을 나가면 그 조율은 방장만 관리한다. 사용자 요청으로 테스트·타입 검사·QA 를 돌리지 않고 배포했다(이미지 빌드의 컴파일만 통과). `DatePollIntegrationTest` 는 코드만 고쳤고, QA 스크립트 `date-poll-ui.js` 의 '멤버에게 버튼 없음' 검사는 옛 권한 기준이다. 되돌리기 이미지 `moyeolog-{app,frontend}:before-pollmembers-20261126`, 백업 `data/backup/db-20261126-023925.sql.gz`.
- **PR**: BE #13, FE #36. 구현은 opus 에이전트 둘(`poll-be`, `poll-fe`)이 했다. 지시서·보고서 `/home/ruraeru/moyeolog-fix/DATEPOLL_BRIEF.md`·`DATEPOLL_REPORT_{BE,FE}.md`·`DATEPOLL_QA.md`.
- **알고 있는 한계**: 같은 IP(같은 와이파이)에서 여럿이 한 모임을 동시에 보면 `api_limit`(10r/s)에 걸려 갱신이 늦을 수 있다(변경 하나마다 탭마다 목록 5개를 다시 부른다). AI 요약 문장은 어색하거나 사실과 다를 수 있다(추천 날짜·이유만 코드가 거른다). 모임장이 격자 칸을 누르면 자기 선택도 바뀐다. 확정된 날은 격자 칸에 따로 표시되지 않는다. 일정이 지워져도 조율의 `scheduleId` 는 남는다. LLM 실패 화면은 QA 에서 눈으로 보지 못했다(백엔드 테스트만).

## 서식 편집기 (feat/rich-editor, 2026-11-26 운영 배포)

마크다운 문법을 몰라도 쓸 수 있게, 원문 칸 + 미리보기 두 칸이던 편집기를 보이는 화면에서 바로 쓰는 편집기 하나로 바꿨다.

- `MOYEOLOG_FE/src/components/RichEditor.tsx`(Tiptap 3.35.0: `@tiptap/react`·`pm`·`starter-kit`·`markdown`·`extension-list`·`extensions`). `value`·`onChange` 는 마크다운이다. **저장 형식은 그대로**라 백엔드·기존 메모·읽기 화면(`@uiw/react-md-editor` 의 `Markdown`)은 바꾸지 않았다.
- 도구 막대: 굵게, 기울임, 취소선, 소제목(H2), 글머리·번호·체크 목록, 인용, 코드, `@`(일정·메모 연결). `**굵게**` 같은 문법을 쳐도 바로 바뀐다.
- `@` 연결: `mentions` 를 주면 `@` 뒤 글자로 일정·메모를 찾아 `[@제목](/memo/id)` 링크로 넣는다(예전과 같은 형식, 저장 때 `extractMentionIds` 가 읽는다). 목록은 클릭으로만 고른다.
- 쓰는 곳: 새 메모(`MemoCreateModal`), 메모 수정(`MemoDetailView`), 새 토픽(`GroupTopicCreateModal`, `@` 연결 없음), `MemoEditModal`(지금 어디서도 쓰지 않는다).
- 본문 모양은 읽기 화면과 같은 `.wmde-markdown` 을 쓰고, 편집기만의 것은 `globals.css` 의 `.rich-editor`(자리표시 글, 체크 목록, 모바일 16px)다.
- **한계**: 표와 밑줄은 지원하지 않는다. 표가 든 메모를 이 편집기로 고쳐 저장하면 표가 깨질 수 있다(배포 때 운영 데이터에 표 0건). 밑줄은 마크다운에 없어 껐다.
- **QA**: `./pw.sh node scripts/rich-editor-ui.js`(26건: 도구 막대, `@` 연결, 저장된 마크다운, 예전 마크다운 메모를 열어 고친 뒤에도 서식 유지, 모바일 16px).
- **배포**: FE #35. 프론트만 올렸다. 되돌리기 이미지 `moyeolog-frontend:before-richeditor-20261126`, 백업 `data/backup/db-20261126-010249.sql.gz`. 운영에서는 컨테이너 정상·도메인 200·번들에 편집기 포함까지 봤고, 로그인한 화면과 실제 아이폰은 확인하지 못했다.

## 2차 QA 와 수정 (2026-11-22)

- QA: 운영과 같은 이미지의 격리 스택(`/home/ruraeru/moyeolog-qa/`, compose 프로젝트 `moyeolog-qa`, 127.0.0.1:3093/3094/8093)에서 에이전트 12개가 567건 실행 → 실패 191건. 결과 JSON `results/`, Figma QA 시트 2차 프레임. 스택은 배포 뒤 내렸다(`docker compose down`, 볼륨 유지). 다시 쓰려면 그 폴더에서 `docker compose up -d`.
- 수정: 에이전트 12개가 영역별 worktree(`/home/ruraeru/moyeolog-fix/`)에서 고치고, 세 레포의 `fix/qa2` 브랜치로 합쳤다. API 계약은 `/home/ruraeru/moyeolog-fix/CONTRACTS.md`.
- 재검증: 실패 191건 전부 재실행 → 실패 0(Kakao 로그인·지도·localhost 이미지 최적화 보류 11). 결과 `results-r2/`.
- 새 기능: 알림(종류별 설정), 친구 1:1 메시지, 다른 사용자 프로필, 도움말, 설정 4개 메뉴(알림·계정 및 보안·화면·언어 및 지역), 일정 주·목록 보기·종료 시각, 댓글 수정, 모임 나가기·삭제·초대 모달·초대 링크 확인 화면.
- 배포(2026-11-23): PR BE #3, FE #5, DEPLOY #6 머지 후 운영 반영. 직전 백업 `data/backup/db-20261123-051450.sql.gz`·`uploads-20261123-051450.tar.gz`. 실제 Kakao 로그인으로 운영 동작 확인.
- 배포 순서(이대로 했다): ① `backup.sh` ② 기존 앱 중지 ③ `migrations/2026-11-22-qa2/pre-deploy.sql` ④ `docker compose up -d --build`(포트 바인딩이 바뀌어 nginx·app 재생성 필요) ⑤ `post-deploy.sql` ⑥ 로그에서 `[topic-image-migration]` 확인 ⑦ crontab 등록.
- 운영 서버 메모리(11GB)가 작다: 에이전트·Playwright 를 12개 동시에 돌리면 서버가 다운된다(2026-11-22). 6개 이하로, 브라우저는 동시 2개 이하로.

## 남은 일

- 고치지 않은 것: customId 변경 기능, robots.txt·sitemap(OG 태그는 2026-11-25 에 넣었다), 앱 전체 영어 번역('언어 및 지역'은 12/24시간 표시만), CSP 의 `'unsafe-eval'`(Kakao 지도 SDK 가 필요한지 확인 못 함).
- 알고 있는 한계: 친구 삭제와 메모 공유가 동시에 오면, 또는 같은 초대를 동시에 두 번 보내면 409(다시 시도하면 됨). `/memo` 는 모임마다 요청을 하나씩 보내 모임이 아주 많으면 rate limit 에 가깝다. 폴링 주기 메시지 5초·토픽 10초·모임 화면 15초·배지 30초. 댓글 멘션을 고른 뒤 입력창으로 포커스가 돌아가지 않는다.
- 외부 노출 확인(2026-11-24): 외부에서 공인 IP `183.109.112.88` 의 3003·8083 으로 직접 연결하면 거부된다(공유기가 넘기지 않음). 같은 곳에서 도메인은 200. nginx 로그 32시간치의 `peer=` 도 Caddy(172.30.1.10)와 서버 안 요청뿐이었다. 공유기 포트 포워딩을 바꾸면 다시 확인한다.
- 알고 있는 노출: 3003 은 `0.0.0.0` 에 열려 있어 LAN·tailscale 기기에서는 Caddy 를 거치지 않고 nginx 에 닿는다(외부 아님). 더 막으려면 방화벽으로 3003 을 172.30.1.10 에서만 받는다.
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
