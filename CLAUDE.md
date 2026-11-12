# MOYEOLOG 배포 레포

메모·일정·모임·친구 서비스 MOYEOLOG의 Docker 배포 구성. 프론트(Next.js)와 백엔드(Spring Boot)는 서브모듈이다.

- 운영 주소: https://moyeolog.ruraeru.xyz
- 서브모듈: `MOYEOLOG_FE` (github.com/ruraeru/MOYEOLOG_FE), `MOYEOLOG_BE` (github.com/ruraeru/MOYEOLOG_BE)
- 현재 작업 브랜치: 세 레포 모두 `fix/qa-findings` (푸시됨, `main` 에는 아직 합치지 않음). 실서비스는 이 브랜치 코드로 돌고 있다.

## 구조

```
외부 Caddy(TLS, 172.30.1.10) ─ moyeolog.ruraeru.xyz ─▶ 이 서버 :3003 ─▶ nginx ─┬─ /api, /uploads ─▶ app:8080 (Spring Boot)
                                                                              └─ /api/auth, /api/search-image, /api/proxy-image, 그 외 ─▶ frontend:3000 (Next.js)
                                                        이 서버 :8083 ─▶ app:8080 (백엔드 직접 접근)
```

- TLS는 외부 Caddy가 종료한다. 이 스택은 HTTP만 다룬다 (certbot 없음).
- 3003은 프론트 컨테이너가 아니라 nginx다. 브라우저가 같은 도메인의 `/api` 를 호출하므로 nginx가 경로로 나눈다.
- 같은 서버에 다른 프로젝트가 3000~3002, 8080~8082 를 쓰고 있다.
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
  - 백엔드 테스트: `docker run --rm -v "$PWD":/src -w /src eclipse-temurin:25-jdk-alpine ./gradlew test --no-daemon` (H2 사용, 64개)
  - 프론트 타입 검사: `node:20-alpine` 컨테이너에서 `npm ci && npx tsc --noEmit`
- DB 접속: `docker exec moyeolog-db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" moyeolog'`
- 백업: `backup.sh`. 수동 덤프는 `data/backup/` (gitignore 대상).

## 꼭 알아야 할 것

- **백엔드에 `application.yml` 이 없다** (gitignore). 운영 설정은 전부 `docker-compose.yml` 의 환경변수로 들어간다. 새 프로퍼티는 `@Value` 기본값을 주고 `application.yml.example` 과 compose 에 추가한다.
- **`INTERNAL_API_SECRET`**: 프론트 서버(NextAuth)가 백엔드 `POST /api/auth/sync` 를 부를 때 `X-Internal-Secret` 헤더로 보낸다. 프론트·백엔드 컨테이너에 같은 값이 있어야 로그인이 된다. nginx 는 `/api/auth/sync`, `/api/auth/refresh` 를 외부에 404 로 막는다.
- **시간**: 일정 시각과 작성 시각은 오프셋 없는 한국 시간 `LocalDateTime` 이다. 백엔드 컨테이너는 `TZ=Asia/Seoul`. 프론트는 `yyyy-MM-dd'T'HH:mm:ss` 로 보낸다 (`toISOString()` 금지).
- **스키마**: `ddl-auto=update`. Hibernate 는 기존 컬럼 타입을 바꾸지 않으므로 타입 변경은 직접 `ALTER TABLE` 해야 한다.
- **nginx `add_header`**: location 안에 `add_header` 가 하나라도 있으면 server 레벨 헤더가 전부 빠진다. 그런 location 에는 `include /etc/nginx/snippets/security-headers.conf;` 를 넣는다.
- **신뢰 프록시**: `set_real_ip_from 172.30.1.10` (Caddy) 하나만 신뢰한다. Caddy 주소가 바뀌면 nginx 접속 로그의 `peer=` 값을 보고 고친다. 범위를 넓히면 `X-Forwarded-For` 조작으로 rate limit 이 우회된다.
- **CSP**: `nginx/conf.d/default.conf` 에 있다. Kakao 지도 SDK 는 `*.kakaocdn.net` 에서 스크립트를 받는다. 외부 리소스를 추가하면 CSP 도 고친다.
- **업로드**: 백엔드가 파일 내용(매직 바이트)으로 JPEG/PNG/GIF/WEBP 만 받고 확장자는 서버가 정한다. nginx 는 `/uploads/` 에서 이미지 확장자만 이미지로 내려주고 나머지는 다운로드로 처리한다. 업로드 볼륨은 uid 1001 소유여야 한다 (백엔드가 non-root 로 실행).
- **Swagger**: 기본으로 꺼져 있다. 필요하면 `.env` 에 `SWAGGER_ENABLED=true`.
- **Kakao 키**: REST API 키(`KAKAO_CLIENT_ID`), Client Secret, JavaScript 키(`NEXT_PUBLIC_KAKAO_MAP_API_KEY`) 는 모두 같은 Kakao 앱의 것이어야 하고, 그 앱에 사이트 도메인과 Redirect URI `https://moyeolog.ruraeru.xyz/api/auth/callback/kakao` 가 등록돼 있어야 한다.
- **git**: 이 서버에는 전역 git 사용자 설정이 없다. 커밋은 `git -c user.name=ruraeru -c user.email=f93335383@gmail.com commit ...` 으로 했다. 푸시는 `gh auth login` 으로 인증돼 있다. 서브모듈을 먼저 푸시하고 배포 레포를 푸시한다.
- **모니터링**: `docker-compose.monitoring.yml` 은 별도 스택. 비밀번호는 `.env` 의 `GRAFANA_ADMIN_PASSWORD`, `DOZZLE_PASSWORD` 로 넣고, UI 는 127.0.0.1 에만 열린다. 지금은 실행하고 있지 않다.

## 지금까지 한 일 (2026-11-12)

1. **Docker 배포 전환**: `.gitmodules` 복구, 포트 3003/8083 할당, nginx 를 HTTP 단일 서버로 변경, 도메인을 `moyeolog.kro.kr` → `moyeolog.ruraeru.xyz` 로 교체, 백엔드 설정을 환경변수로 주입.
2. **Kakao 연동 정리**: 새 Kakao 앱의 키 3개로 교체, CSP 에 `*.kakaocdn.net` 허용.
3. **QA** (에이전트 3개: 백엔드 API, 보안·배포 설정, 프론트·연동) 후 발견 사항 수정:
   - 보안: `/api/auth/sync` 무인증 계정 탈취, 이미지 프록시 SSRF, 업로드 저장형 XSS, 그룹 비멤버의 메모·일정 읽기/쓰기, rate limit 우회, 보안 헤더 누락.
   - 기능: 설정 페이지 401, 일정 9시간 밀림, 토큰 갱신 후 401 고착, 초대 중복 수락, 이메일 없는 친구 초대 500, 긴 메모 저장 실패, 초대 링크 로그인 후 유실.
   - 권한·설계: 공유받은 메모 읽기 전용, 사용자별 즐겨찾기, 그룹 수정 방장 전용, 오류 응답을 500 대신 4xx 로, 리프레시 토큰 구조 개편.
   - 추가된 API: `DELETE /api/memos/{id}/share/{targetUserId}`, `DELETE /api/groups/{id}/members/me`, `DELETE /api/groups/{id}`. 프론트 화면은 아직 없다.
4. **배포와 재검증**: DB·업로드 백업 후 QA 테스트 데이터 삭제, 컬럼 타입 변경, 새 이미지 배포. QA 에서 재현됐던 항목을 같은 요청으로 다시 확인해 통과.
5. **커밋·푸시**: 세 레포 `fix/qa-findings`.

## 남은 일

- `fix/qa-findings` 를 `main` 에 합치기 (PR 미생성).
- 고치지 않은 것: customId 변경 기능, 토픽 이미지가 base64 로 DB 에 저장되는 구조, robots/OG 태그, 공유 해제·모임 나가기·모임 삭제 화면, 모임 초대를 보내는 화면(`GroupInviteModal` 이 어디에도 연결돼 있지 않음), 프론트 lint 오류 1건(`AlertContainer.tsx`, 기존 문제).
- 확인하지 못한 것: 실제 Kakao 로그인 완료 흐름과 브라우저 화면 동작(자동화 브라우저 스크린샷으로 홈·메모·설정 렌더링만 확인), 8083/3003 포트가 외부 인터넷에서 직접 닿는지.
- 대화에 평문으로 올라온 키(Gemini, Kakao Client Secret, Kakao 어드민 키)는 재발급 권장.
- `JWT_ACCEPT_LEGACY_TOKENS` 는 기본 true (배포 전 발급된 토큰 허용). 2026-11-19 이후 false 로 바꿔도 된다.

## 시연 영상 (진행 중, 중단 상태)

제출용 5분 시연 영상. 자막만 넣고 음성은 없다. 실제 계정 4개(황태우, 박재선, 동주, 김수민)로 찍기로 했다.

- 작업 폴더: `/home/ruraeru/moyeolog-demo/` (레포 밖)
  - `run.sh`: 도구 컨테이너(`moyeolog-demo-tools`: Playwright 1.49, ffmpeg, Noto CJK 폰트)에서 스크립트 실행
  - `scripts/make-sessions.js`: 백엔드 sync 로 토큰을 받아 NextAuth 세션 쿠키를 만들고 `state/*.json` 에 저장 (Kakao 로그인은 자동화 불가). 토큰은 24시간 유효하므로 다시 찍을 때 재실행한다.
  - `scripts/explore.js`: 지정한 계정으로 페이지 스크린샷
- 계획: `/home/ruraeru/.claude/plans/effervescent-plotting-mccarthy.md`
- 구성: 주인공 황태우, 상대역 김수민. 로그인 → 설정 → 친구 요청·수락 → 메모 작성·AI 분석·공유 → 모임 생성·초대 링크 가입 → 일정(장소 검색·지도) → 모임 토픽·댓글·AI 요약 → 홈.
- 완료: 도구 이미지, 세션 4개, 홈·메모·설정 화면 렌더링 확인.
- 중단 지점: 시연 데이터 넣기(황태우 계정에 예시 메모 3개·일정 2개, 황태우↔동주 친구) 직전에 사용자가 멈췄다. 진행 여부를 확인받아야 한다. 녹화 스크립트와 편집은 아직 없다.
- 주의: 황태우 계정에 테스트성 메모("아아아아")와 일정("ㅂㅈㄷㅂㅈㄷ")이 있어 영상에 보인다. 실제 데이터라 지우지 않았다.
