# ==============================================================================
# MOYEOLOG Automatic Backup Script (Windows PowerShell)
# ==============================================================================

$ErrorActionPreference = "Stop"

# Script directory path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Configurable paths
$BackupDir = ".\data\backups"
$DbContainerName = "moyeolog-db"

# Create backup directory if it doesn't exist
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

# Load .env file
$EnvFile = ".\.env"
if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            $key = $parts[0].Trim()
            $value = $parts[1].Trim()
            # Remove enclosing quotes if any
            if ($value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Substring(1, $value.Length - 2) }
            if ($value.StartsWith("'") -and $value.EndsWith("'")) { $value = $value.Substring(1, $value.Length - 2) }
            [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
} else {
    Write-Error "Error: .env file not found."
    Exit 1
}

# Set default values if not defined in env
$DbName = if ($env:MYSQL_DATABASE) { $env:MYSQL_DATABASE } else { "moyeolog" }
$DbPass = $env:MYSQL_ROOT_PASSWORD

if (-not $DbPass) {
    Write-Error "Error: MYSQL_ROOT_PASSWORD is not set in .env."
    Exit 1
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$TempSql = "$BackupDir\temp_db_$Timestamp.sql"
$ArchiveFile = "$BackupDir\backup_$Timestamp.zip"

Write-Host "### Starting backup process..."

# 1. Database dump
Write-Host "--> Dumping database ($DbName)..."
docker exec $DbContainerName mysqldump -u root -p$DbPass $DbName > $TempSql

# 2. Archive database dump
Write-Host "--> Archiving files..."
Compress-Archive -Path $TempSql -DestinationPath $ArchiveFile -Force

# Clean up temporary SQL file
Remove-Item $TempSql -Force

Write-Host "--> Backup successfully saved to: $ArchiveFile"

# 3. Retention policy: Remove backups older than 7 days
Write-Host "--> Cleaning up old backups (older than 7 days)..."
$LimitDate = (Get-Date).AddDays(-7)
Get-ChildItem -Path $BackupDir -Filter "backup_*.zip" | Where-Object {
    $_.LastWriteTime -lt $LimitDate
} | Remove-Item -Force

Write-Host "### Backup process completed successfully!"
