#!/bin/bash

set -euo pipefail

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
if [[ ! -f .env ]]; then
    echo "Missing .env file" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${db_host:?db_host is required}"
: "${db_user:?db_user is required}"
: "${db_pass:?db_pass is required}"
: "${max_parallel:?max_parallel is required}"
: "${max_backups:?max_backups is required}"
: "${backup_dir:?backup_dir is required}"

max_parallel_cap="${max_parallel_cap:-16}"
mysql_connection_reserve="${mysql_connection_reserve:-20}"

if ! [[ "$max_backups" =~ ^[0-9]+$ ]]; then
    echo "max_backups must be a non-negative integer" >&2
    exit 1
fi

if ! [[ "$max_parallel_cap" =~ ^[0-9]+$ ]] || ((max_parallel_cap < 1)); then
    echo "max_parallel_cap must be an integer >= 1" >&2
    exit 1
fi

if ! [[ "$mysql_connection_reserve" =~ ^[0-9]+$ ]]; then
    echo "mysql_connection_reserve must be a non-negative integer" >&2
    exit 1
fi

# Config
timestamp="$(date +"%Y%m%d-%H%M%S")"

# Make sure backup directory exists
mkdir -p "$backup_dir/$timestamp"

mysql_cnf="$(mktemp "${TMPDIR:-/tmp}/mysql-backup-XXXXXX.cnf")"
chmod 600 "$mysql_cnf"
cat > "$mysql_cnf" <<EOF
[client]
host=$db_host
user=$db_user
password=$db_pass
EOF
trap 'rm -f "$mysql_cnf"' EXIT

unset db_pass

resolve_parallel_jobs() {
    local max_parallel_value="$1"
    local max_parallel_cap_value="$2"
    local connection_reserve="$3"
    local mysql_cnf_path="$4"

    if [[ "$max_parallel_value" != "auto" ]]; then
        if ! [[ "$max_parallel_value" =~ ^[0-9]+$ ]] || ((max_parallel_value < 1)); then
            echo "max_parallel must be a positive integer or 'auto'" >&2
            return 1
        fi
        echo "$max_parallel_value"
        return 0
    fi

    local cpu_count
    cpu_count="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 1)"
    if ! [[ "$cpu_count" =~ ^[0-9]+$ ]] || ((cpu_count < 1)); then
        cpu_count=1
    fi

    local db_max_connections
    db_max_connections="$(mysql --defaults-extra-file="$mysql_cnf_path" -Nse "SELECT @@max_connections;" 2>/dev/null || true)"
    if ! [[ "$db_max_connections" =~ ^[0-9]+$ ]] || ((db_max_connections < 1)); then
        echo "Could not determine MySQL max_connections for auto max_parallel" >&2
        return 1
    fi

    local connection_budget=$((db_max_connections - connection_reserve))
    if ((connection_budget < 1)); then
        connection_budget=1
    fi

    local jobs="$cpu_count"
    if ((connection_budget < jobs)); then
        jobs="$connection_budget"
    fi
    if ((max_parallel_cap_value < jobs)); then
        jobs="$max_parallel_cap_value"
    fi
    if ((jobs < 1)); then
        jobs=1
    fi

    echo "$jobs"
}

# Function to cleanup old backups
cleanup_old_backups() {
    local backup_root="$1"
    local keep_count="$2"
    local -a backups=()

    if [[ -z "$backup_root" || "$backup_root" == "/" ]]; then
        echo "Invalid backup_dir for cleanup: '$backup_root'" >&2
        return 1
    fi

    if [[ ! -d "$backup_root" ]]; then
        echo "Backup directory does not exist for cleanup: $backup_root" >&2
        return 1
    fi

    local dir_name
    for dir_name in "$backup_root"/*; do
        [[ -d "$dir_name" ]] || continue
        dir_name="$(basename "$dir_name")"
        [[ "$dir_name" =~ ^[0-9]{8}-[0-9]{6}$ ]] || continue
        backups+=("$dir_name")
    done

    if ((${#backups[@]} == 0)); then
        return 0
    fi

    IFS=$'\n' backups=($(printf '%s\n' "${backups[@]}" | sort -r))
    unset IFS
    local num_backups="${#backups[@]}"

    if ((num_backups <= keep_count)); then
        return 0
    fi

    local i
    for ((i = keep_count; i < num_backups; i++)); do
        echo "Deleting old backup: ${backups[$i]}"
        rm -rf -- "$backup_root/${backups[$i]}"
    done
}

# Define function for DB export
backup_db() {
    local db="$1"
    local backup_timestamp="$2"
    local backup_root="$3"
    local mysql_cnf_path="$4"

    echo "Backing up $db"
    if mysqldump \
        --defaults-extra-file="$mysql_cnf_path" \
        --single-transaction \
        --skip-lock-tables \
        --databases "$db" \
        | gzip > "$backup_root/$backup_timestamp/$db.sql.gz"; then
        echo "Backup of $db completed"
    else
        echo "Backup of $db failed" >&2
        return 1
    fi
}
export -f backup_db

parallel_jobs="$(resolve_parallel_jobs "$max_parallel" "$max_parallel_cap" "$mysql_connection_reserve" "$mysql_cnf")"
echo "Using $parallel_jobs parallel job(s)"

# Get list of all databases
databases=()
while IFS= read -r db; do
    [[ -n "$db" ]] && databases+=("$db")
done < <(
    mysql --defaults-extra-file="$mysql_cnf" -Nse "SHOW DATABASES;" \
        | grep -Ev "^(information_schema|performance_schema|mysql|sys|vapor)$" || true
)

# Run export job
if ((${#databases[@]} == 0)); then
    echo "No user databases found for backup"
else
    printf '%s\n' "${databases[@]}" \
        | parallel --halt soon,fail=1 -j "$parallel_jobs" \
            backup_db {} "$timestamp" "$backup_dir" "$mysql_cnf"
fi

# Clean up old backups
echo "Cleaning up old backups"
cleanup_old_backups "$backup_dir" "$max_backups"

# Done
echo -e "\n\nBackup completed\n"
