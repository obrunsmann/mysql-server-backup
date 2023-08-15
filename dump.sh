#!/bin/bash

# MIT License

# Copyright (c) 2023 Oliver Brunsmann

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

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