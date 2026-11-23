#!/usr/bin/env bash
# ==============================================================================
# MOYEOLOG 백업 (DB + 업로드 파일)
#
#   ./backup.sh
#
# - DB: moyeolog-db 컨테이너 안에서 mysqldump → data/backup/db-<시각>.sql.gz
# - 업로드: moyeolog_app_images 볼륨을 읽기 전용으로 붙여 tar → data/backup/uploads-<시각>.tar.gz
# - 백업 파일은 600, 폴더는 700. 비밀번호는 명령줄에 올리지 않는다
#   (DB 컨테이너가 이미 가진 MYSQL_ROOT_PASSWORD 를 컨테이너 안에서 MYSQL_PWD 로 넘긴다. .env 를 읽지 않는다).
# - RETENTION_DAYS(기본 14)일이 지난 db-*.sql.gz / uploads-*.tar.gz 만 지운다. 손으로 만든 덤프는 건드리지 않는다.
# - 주기 실행(crontab)은 README.md 의 "백업" 참고.
#
# 바꿀 수 있는 값(환경변수): BACKUP_DIR, RETENTION_DAYS, DB_CONTAINER, UPLOAD_VOLUME, TAR_IMAGE
# ==============================================================================
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/data/backup}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
DB_CONTAINER="${DB_CONTAINER:-moyeolog-db}"
UPLOAD_VOLUME="${UPLOAD_VOLUME:-moyeolog_app_images}"
# 업로드 볼륨을 tar 로 묶을 때 쓰는 이미지. 스택이 이미 받아 둔 nginx 이미지를 쓴다(따로 받을 필요 없음).
TAR_IMAGE="${TAR_IMAGE:-nginx:1.25-alpine}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

case "$RETENTION_DAYS" in
  ''|*[!0-9]*) log "오류: RETENTION_DAYS 는 숫자여야 합니다 ($RETENTION_DAYS)"; exit 1 ;;
esac

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# 동시에 두 번 돌지 않게 (cron 이 겹치거나 손으로 돌릴 때)
exec 9>"$BACKUP_DIR/.backup.lock"
if ! flock -n 9; then
  log "다른 백업이 진행 중이라 건너뜁니다."
  exit 1
fi

TS="$(date +%Y%m%d-%H%M%S)"
DB_FILE="$BACKUP_DIR/db-$TS.sql.gz"
UPLOAD_FILE="$BACKUP_DIR/uploads-$TS.tar.gz"

# 중간에 실패하면 반쯤 쓴 파일을 남기지 않는다
cleanup() {
  rm -f "$DB_FILE.part" "$UPLOAD_FILE.part"
}
trap cleanup EXIT

if ! docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null | grep -q true; then
  log "오류: DB 컨테이너 $DB_CONTAINER 가 실행 중이 아닙니다."
  exit 1
fi
if ! docker volume inspect "$UPLOAD_VOLUME" >/dev/null 2>&1; then
  log "오류: 업로드 볼륨 $UPLOAD_VOLUME 이 없습니다."
  exit 1
fi

# 1. DB
log "DB 덤프 시작 ($DB_CONTAINER)"
# 작은따옴표 안의 $MYSQL_* 는 호스트가 아니라 컨테이너 안에서 풀린다.
docker exec "$DB_CONTAINER" sh -c '
  export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
  exec mysqldump -uroot --single-transaction --quick --routines --triggers --events \
    --default-character-set=utf8mb4 --no-tablespaces "${MYSQL_DATABASE:-moyeolog}"
' | gzip -c > "$DB_FILE.part"
# 덤프가 끝까지 쓰였는지 확인 (mysqldump 는 정상 종료 시 마지막 줄에 "Dump completed" 를 남긴다)
if ! gzip -dc "$DB_FILE.part" | tail -n 1 | grep -q "Dump completed"; then
  log "오류: DB 덤프가 끝까지 쓰이지 않았습니다."
  exit 1
fi
mv "$DB_FILE.part" "$DB_FILE"
log "DB 덤프 완료: $DB_FILE ($(du -h "$DB_FILE" | cut -f1))"

# 2. 업로드 파일
log "업로드 볼륨 백업 시작 ($UPLOAD_VOLUME)"
docker run --rm --network none --entrypoint tar \
  -v "$UPLOAD_VOLUME":/data:ro "$TAR_IMAGE" -czf - -C /data . > "$UPLOAD_FILE.part"
mv "$UPLOAD_FILE.part" "$UPLOAD_FILE"
log "업로드 백업 완료: $UPLOAD_FILE ($(du -h "$UPLOAD_FILE" | cut -f1))"

# 3. 보존 기간이 지난 자동 백업 삭제
log "${RETENTION_DAYS}일 지난 백업 정리"
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'db-*.sql.gz' -o -name 'uploads-*.tar.gz' \) \
  -mtime +"$RETENTION_DAYS" -print -delete

log "백업 완료"
