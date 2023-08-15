#!/bin/bash

# Load env file
export $(cat .env | xargs)

# Config
timestamp=$(date +"%Y%m%d-%H%M%S")


# Run backup
mkdir -p "backup/$timestamp"

# Get list of all databases
databases=$(mysql -h $db_host -u $db_user --password="$db_pass" -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys|vapor)")

# Define function for DB Export
backup_db() {
    local db="$1"
    local db_user="$2"
    local db_pass="$3"
    local db_host="$4"
    local timestamp="$5"

    echo "Backing up $db"
    mysqlpump \
        --user="$db_user" --password="$db_pass" \
        --host="$db_host" \
        --set-gtid-purged=ON \
        --exclude-tables=cache,cache_locks,sessions,jobs,password_reset_tokens \
        --compression-algorithms=zlib,zstd \
        --default-parallelism=8 \
        $db | gzip > "backup/$timestamp/$db.sql.gz"

    echo "Backup of $db completed"
}
export -f backup_db

# Run export job
echo "$databases" | parallel -j $max_parallel backup_db {} $db_user $db_pass $db_host $timestamp

echo -e "\n\nBackup completed\n"