# ==============================================================================
# MOYEOLOG 백업 (Windows PowerShell). backup.sh 와 같은 일을 한다.
#
#   .\backup.ps1
#
# - DB: moyeolog-db 컨테이너 안에서 mysqldump | gzip → docker cp → data\backup\db-<시각>.sql.gz
#   (PowerShell 리다이렉션은 인코딩을 바꾸므로 덤프는 컨테이너 안에서 파일로 만든 뒤 꺼낸다)
# - 업로드: moyeolog_app_images 볼륨을 읽기 전용으로 붙여 tar → data\backup\uploads-<시각>.tar.gz
# - 비밀번호는 명령줄에 올리지 않는다(DB 컨테이너의 MYSQL_ROOT_PASSWORD 를 컨테이너 안에서 MYSQL_PWD 로 넘긴다).
# - 백업 폴더는 현재 사용자만 접근하도록 ACL 을 좁힌다.
# - RetentionDays(기본 14)일이 지난 db-*.sql.gz / uploads-*.tar.gz 만 지운다.
# ==============================================================================
param(
    [string]$BackupDir = (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "data\backup"),
    [int]$RetentionDays = 14,
    [string]$DbContainer = "moyeolog-db",
    [string]$UploadVolume = "moyeolog_app_images",
    [string]$TarImage = "nginx:1.25-alpine"
)

$ErrorActionPreference = "Stop"

function Log($msg) { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" }
function Check($what) { if ($LASTEXITCODE -ne 0) { throw "$what 실패 (exit $LASTEXITCODE)" } }

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}
# 현재 사용자만 접근 (상속 끊고 본인 전체 권한만)
icacls $BackupDir /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null

$running = docker inspect -f "{{.State.Running}}" $DbContainer 2>$null
if ($running -ne "true") { throw "DB 컨테이너 $DbContainer 가 실행 중이 아닙니다." }
docker volume inspect $UploadVolume *> $null
if ($LASTEXITCODE -ne 0) { throw "업로드 볼륨 $UploadVolume 이 없습니다." }

$Ts = Get-Date -Format "yyyyMMdd-HHmmss"
$DbFile = Join-Path $BackupDir "db-$Ts.sql.gz"
$UploadFile = "uploads-$Ts.tar.gz"
$Tmp = "/tmp/moyeolog-backup-$Ts.sql.gz"

# 1. DB
Log "DB 덤프 시작 ($DbContainer)"
$dump = 'set -e; export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"; umask 077; ' +
        'mysqldump -uroot --single-transaction --quick --routines --triggers --events ' +
        '--default-character-set=utf8mb4 --no-tablespaces "${MYSQL_DATABASE:-moyeolog}" > /tmp/dump.sql; ' +
        'tail -n 1 /tmp/dump.sql | grep -q "Dump completed"; gzip -c /tmp/dump.sql > ' + $Tmp + '; rm -f /tmp/dump.sql'
try {
    docker exec $DbContainer sh -c $dump; Check "mysqldump"
    docker cp "${DbContainer}:$Tmp" $DbFile; Check "docker cp"
} finally {
    docker exec $DbContainer rm -f $Tmp /tmp/dump.sql | Out-Null
}
Log "DB 덤프 완료: $DbFile"

# 2. 업로드 파일
Log "업로드 볼륨 백업 시작 ($UploadVolume)"
$absBackup = (Resolve-Path $BackupDir).Path
docker run --rm --network none --entrypoint tar -v "${UploadVolume}:/data:ro" -v "${absBackup}:/backup" `
    $TarImage -czf "/backup/$UploadFile" -C /data .
Check "업로드 tar"
Log "업로드 백업 완료: $(Join-Path $BackupDir $UploadFile)"

# 3. 보존 기간이 지난 자동 백업 삭제
Log "${RetentionDays}일 지난 백업 정리"
$limit = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem -Path $BackupDir -File | Where-Object {
    ($_.Name -like "db-*.sql.gz" -or $_.Name -like "uploads-*.tar.gz") -and $_.LastWriteTime -lt $limit
} | Remove-Item -Force

Log "백업 완료"
