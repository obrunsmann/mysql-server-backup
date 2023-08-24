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

# Make sure backup directory exists
mkdir -p "backup/$timestamp"

# Function to cleanup old backups
cleanup_old_backups() {
    local backup_dir="backup/"
    local backups=($(ls -t "$backup_dir" | grep "^[0-9]*-[0-9]*$"))
    local num_backups=${#backups[@]}

    if [ $num_backups -gt $max_backups ]; then
        local num_to_delete=$((num_backups - max_backups))
        for ((i = 0; i < num_to_delete; i++)); do
            echo "Deleting old backup: ${backups[$i]}"
            rm -r "$backup_dir/${backups[$i]}"
        done
    fi
}

# Define function for DB Export
backup_db() {
    local db="$1"
    local db_user="$2"
    local db_pass="$3"
    local db_host="$4"
    local timestamp="$5"

    echo "Backing up $db"
    mysqldump \
        --user="$db_user" --password="$db_pass" \
        --host="$db_host" \
        --single-transaction \
        --skip-lock-tables \
        $db | gzip > "backup/$timestamp/$db.sql.gz"

    echo "Backup of $db completed"
}
export -f backup_db

# Get list of all databases
databases=$(mysql -h $db_host -u $db_user --password="$db_pass" -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys|vapor)")

# Run export job
echo "$databases" | parallel -j $max_parallel backup_db {} $db_user $db_pass $db_host $timestamp

# Clean up old backups
echo "Cleaning up old backups"
cleanup_old_backups

# Done
echo -e "\n\nBackup completed\n"