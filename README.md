# MOYEOLOG 배포

메모·일정·모임·친구 서비스 **모여로그(MOYEOLOG)** 의 Docker 배포 구성입니다. 프론트엔드와 백엔드는 서브모듈로 들어 있고, 이 레포는 그 둘과 DB, nginx 를 한 번에 띄우는 설정을 담습니다.

- 운영 주소: https://moyeolog.ruraeru.xyz
- 프론트엔드: [MOYEOLOG_FE](https://github.com/ruraeru/MOYEOLOG_FE) (Next.js 16, NextAuth, Tailwind v4)
- 백엔드: [MOYEOLOG_BE](https://github.com/ruraeru/MOYEOLOG_BE) (Spring Boot, MySQL 8.0)

## 구조

```
브라우저 ─ HTTPS ─▶ 외부 Caddy (TLS 종료)
                      │
                      ▼
               이 서버 :3003 ─▶ nginx ─┬─ /api, /uploads ─────────────────────────────▶ app:8080 (Spring Boot)
                                       └─ /api/auth, /api/search-image,
                                          /api/proxy-image, 그 외 모든 경로 ─▶ frontend:3000 (Next.js)
               이 서버 :8083 ─▶ app:8080 (백엔드 직접 접근)
                                       app ─▶ db:3306 (MySQL)
```

| 서비스 | 컨테이너 | 역할 |
| --- | --- | --- |
| `nginx` | `moyeolog-nginx` | 경로별 라우팅, 보안 헤더·CSP, rate limit, `/uploads` 정적 제공 |
| `frontend` | `moyeolog-frontend` | Next.js 화면과 NextAuth(카카오 로그인) |
| `app` | `moyeolog-app` | REST API, 파일 업로드, Gemini 요약 |
| `db` | `moyeolog-db` | MySQL 8.0 |

- TLS 는 외부 Caddy 가 처리합니다. 이 스택은 HTTP 만 다루고 certbot 은 없습니다.
- 브라우저는 같은 도메인의 `/api` 를 부르고, nginx 가 경로로 프론트와 백엔드를 나눕니다.
- compose 프로젝트 이름은 `moyeolog` 입니다. 볼륨은 `moyeolog_db_data`(DB), `moyeolog_app_images`(업로드 파일), `moyeolog_fe_image_cache`(이미지 캐시)입니다.

## 처음 설치

필요한 것은 Docker 와 Docker Compose 뿐입니다. 호스트에 Node 나 JDK 는 없어도 됩니다.

```bash
git clone --recurse-submodules https://github.com/ruraeru/MOYEOLOG_DEPLOY.git
cd MOYEOLOG_DEPLOY

cp .env.example .env      # 값을 채운다 (.env 는 git 에 올라가지 않는다)
docker compose up -d --build
```

이미 클론했다면 `git submodule update --init` 으로 서브모듈을 받습니다.

### 환경변수

전체 목록과 설명은 [`.env.example`](.env.example) 에 있습니다. 꼭 채워야 하는 값은 다음과 같습니다.

| 변수 | 설명 |
| --- | --- |
| `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`, `SPRING_DATASOURCE_PASSWORD` | DB 비밀번호. `SPRING_DATASOURCE_PASSWORD` 는 `MYSQL_PASSWORD` 와 같은 값 |
| `JWT_SECRET` | 백엔드 토큰 서명 키 (긴 랜덤 문자열) |
| `NEXTAUTH_SECRET` | NextAuth 세션 암호화 키 (긴 랜덤 문자열) |
| `INTERNAL_API_SECRET` | 프론트 서버가 백엔드 `/api/auth/sync` 를 부를 때 쓰는 공유 시크릿. 프론트와 백엔드에 같은 값이 들어가야 로그인이 된다 |
| `KAKAO_CLIENT_ID`, `KAKAO_CLIENT_SECRET` | 카카오 로그인 (REST API 키, Client Secret) |
| `NEXT_PUBLIC_KAKAO_MAP_API_KEY` | 카카오 지도 (JavaScript 키) |
| `GEMINI_API_KEY` | 메모 요약·OCR |

랜덤 시크릿은 `openssl rand -base64 48` 로 만들 수 있습니다.

> `NEXT_PUBLIC_*` 값은 프론트 **빌드 시점**에 번들에 들어갑니다. 바꾸면 `docker compose up -d --build frontend` 로 다시 빌드해야 합니다.

### 카카오 앱 설정

REST API 키, Client Secret, JavaScript 키는 모두 **같은 카카오 앱**의 것이어야 합니다. 그 앱의 [Kakao Developers](https://developers.kakao.com) 콘솔에 다음을 등록합니다.

- 사이트 도메인: `https://moyeolog.ruraeru.xyz`
- Redirect URI: `https://moyeolog.ruraeru.xyz/api/auth/callback/kakao`

### 포트

| 변수 | 기본값 | 용도 |
| --- | --- | --- |
| `FRONTEND_PORT` | 3003 | 서비스 진입점 (nginx). 외부 프록시가 이 포트로 연결 |
| `BACKEND_PORT` | 8083 | 백엔드 직접 접근 |

같은 서버에서 다른 프로젝트가 3000~3002, 8080~8082 를 쓰고 있어 피했습니다.

## 업데이트와 배포

코드는 각 서브모듈 레포에서 고치고 `main` 에 머지합니다. 그다음 이 레포의 서브모듈 포인터를 올리고 다시 빌드합니다.

```bash
# 1. 서브모듈을 각 레포의 main 최신으로
git submodule update --remote MOYEOLOG_FE MOYEOLOG_BE
git add MOYEOLOG_FE MOYEOLOG_BE
git commit -m "서브모듈 갱신"
git push

# 2. 바뀐 서비스만 다시 빌드
docker compose up -d --build frontend   # 또는 app

# 3. 컨테이너가 새로 만들어지면 nginx 의 upstream IP 를 갱신
docker exec moyeolog-nginx nginx -s reload
```

- `frontend` 는 `app` 에 의존하므로 프론트만 다시 띄워도 백엔드가 같이 재시작될 수 있습니다. 몇 초 동안 API 가 응답하지 않을 수 있습니다.
- 푸시할 때는 서브모듈 레포를 먼저 푸시하고 이 레포를 나중에 푸시합니다. 순서가 바뀌면 존재하지 않는 커밋을 가리키게 됩니다.
- 배포 뒤 확인: `docker compose ps` 에서 모두 `healthy` 인지 보고, `curl -I https://moyeolog.ruraeru.xyz/` 가 200 인지 봅니다.

### 테스트와 검사 (Docker 로 실행)

```bash
# 백엔드 테스트 (H2 사용)
cd MOYEOLOG_BE
docker run --rm -v "$PWD":/src -w /src eclipse-temurin:25-jdk-alpine ./gradlew test --no-daemon

# 프론트 타입 검사와 빌드
cd MOYEOLOG_FE
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/app -w /app node:20-alpine \
  sh -c "npm ci && npx tsc --noEmit && npx next build"
```

## 운영

### 로그

```bash
docker compose logs -f app          # 백엔드
docker compose logs -f frontend     # 프론트
docker compose logs -f nginx        # 접속 로그 (peer= 는 실제 접속한 프록시 주소)
```

### DB 접속

```bash
docker exec -it moyeolog-db sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" moyeolog'
```

스키마는 `ddl-auto=update` 로 관리됩니다. Hibernate 는 이미 있는 컬럼의 타입을 바꾸지 않으므로, 컬럼 타입을 바꿀 때는 직접 `ALTER TABLE` 을 실행합니다.

### 백업

```bash
./backup.sh      # Windows 는 backup.ps1
```

`backup.sh` 는 **DB 만** 덤프해서 `data/backups/backup_<시각>.tar.gz` 로 저장하고, 7일이 지난 백업은 지웁니다. 업로드 파일은 따로 백업합니다.

```bash
docker run --rm -v moyeolog_app_images:/d:ro -v "$PWD/data/backups":/b alpine \
  tar czf /b/uploads_$(date +%Y%m%d_%H%M%S).tar.gz -C /d .
```

`data/` 는 git 에 올라가지 않습니다. 정기 백업이 필요하면 cron 에 `backup.sh` 를 등록합니다.

### 모니터링 (선택)

Prometheus, Grafana, cAdvisor, Dozzle 은 별도 스택입니다. `.env` 에 `GRAFANA_ADMIN_PASSWORD`, `DOZZLE_PASSWORD` 를 넣은 뒤 실행합니다. UI 는 `127.0.0.1` 에만 열립니다.

```bash
docker compose -f docker-compose.monitoring.yml up -d
```

### 부하 테스트 (선택)

[`load-test.js`](load-test.js) 는 k6 시나리오입니다. 운영 주소에 직접 요청하므로 사용자가 적은 시간에 돌립니다.

```bash
docker run --rm -i grafana/k6 run - < load-test.js
```

## 알아 둘 것

- **백엔드 설정 파일이 없습니다.** `application.yml` 은 git 에 없고, 운영 설정은 전부 `docker-compose.yml` 의 환경변수로 들어갑니다. 새 설정은 `@Value` 기본값을 주고 `application.yml.example` 과 compose 에 함께 추가합니다.
- **시간대**: 일정 시각과 작성 시각은 오프셋 없는 한국 시간(`LocalDateTime`)입니다. 백엔드는 `TZ=Asia/Seoul` 로 돌고, 프론트는 `yyyy-MM-dd'T'HH:mm:ss` 형식으로 보냅니다 (`toISOString()` 을 쓰면 9시간 밀립니다).
- **내부 API**: nginx 는 `/api/auth/sync`, `/api/auth/refresh` 를 외부에 404 로 막습니다. 프론트 서버만 내부 네트워크로 부릅니다.
- **신뢰 프록시**: nginx 는 외부 Caddy 주소 하나만 `set_real_ip_from` 으로 신뢰합니다. Caddy 주소가 바뀌면 접속 로그의 `peer=` 값을 보고 [`nginx/conf.d/default.conf`](nginx/conf.d/default.conf) 를 고칩니다. 범위를 넓히면 `X-Forwarded-For` 조작으로 rate limit 이 우회됩니다.
- **CSP**: `nginx/conf.d/default.conf` 에 있습니다. 외부 스크립트·이미지·폰트를 추가하면 CSP 도 같이 고칩니다. 카카오 지도 SDK 는 `*.kakaocdn.net` 에서 스크립트를 받습니다.
- **nginx `add_header`**: location 안에 `add_header` 가 하나라도 있으면 server 레벨 헤더가 전부 빠집니다. 그런 location 에는 `include /etc/nginx/snippets/security-headers.conf;` 를 넣습니다.
- **업로드**: 백엔드는 파일 내용(매직 바이트)으로 JPEG/PNG/GIF/WEBP 만 받고 확장자는 서버가 정합니다. 백엔드가 non-root(uid 1001)로 돌므로 업로드 볼륨도 uid 1001 소유여야 합니다.
- **Swagger** 는 기본으로 꺼져 있습니다. 필요하면 `.env` 에 `SWAGGER_ENABLED=true` 를 넣고 `app` 을 다시 띄웁니다.

## 문제 해결

| 증상 | 확인할 것 |
| --- | --- |
| 카카오 로그인 후 오류 페이지 | 카카오 앱의 Redirect URI·도메인 등록, 세 키가 같은 앱 것인지, `INTERNAL_API_SECRET` 이 프론트·백엔드에 같은지 |
| 컨테이너 재생성 뒤 502 | `docker exec moyeolog-nginx nginx -s reload` |
| 지도가 안 뜸 | `NEXT_PUBLIC_KAKAO_MAP_API_KEY` 가 JavaScript 키인지, 바꾼 뒤 `--build` 했는지, 브라우저 콘솔의 CSP 오류 |
| 일정 시각이 9시간 어긋남 | 프론트가 `toISOString()` 으로 보내고 있는지, 백엔드 `TZ` |
| 이미지 업로드 실패 | 업로드 볼륨 소유자(uid 1001), 파일 형식 |
