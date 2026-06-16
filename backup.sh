#!/bin/bash

# ==============================================================================
# MOYEOLOG Automatic Backup Script (Linux/Unix)
# ==============================================================================

# Exit on error
set -e

# Resolve directory path of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configurable paths
BACKUP_DIR="./data/backups"
DB_CONTAINER_NAME="moyeolog-db"

# Load environment variables from .env
if [ -f .env ]; then
  # Read .env line by line to support values with spaces
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found."
  exit 1
fi

# Set default values if not defined in .env
DB_NAME=${MYSQL_DATABASE:-moyeolog}
DB_PASS=${MYSQL_ROOT_PASSWORD}

if [ -z "$DB_PASS" ]; then
  echo "Error: MYSQL_ROOT_PASSWORD is not set in .env."
  exit 1
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEMP_SQL="$BACKUP_DIR/temp_db_$TIMESTAMP.sql"
ARCHIVE_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

echo "### Starting backup process..."

# 1. Database dump
echo "--> Dumping database ($DB_NAME)..."
docker exec "$DB_CONTAINER_NAME" mysqldump -u root -p"$DB_PASS" "$DB_NAME" > "$TEMP_SQL"

# 2. Archive database dump & local directories
echo "--> Archiving files..."
# Create archive containing the SQL dump
tar -czf "$ARCHIVE_FILE" -C "$BACKUP_DIR" "temp_db_$TIMESTAMP.sql"

# Clean up temporary SQL file
rm "$TEMP_SQL"

echo "--> Backup successfully saved to: $ARCHIVE_FILE"

# 3. Retention policy: Remove backups older than 7 days
echo "--> Cleaning up old backups (older than 7 days)..."
find "$BACKUP_DIR" -name "backup_*.tar.gz" -type f -mtime +7 -delete

echo "### Backup process completed successfully!"
