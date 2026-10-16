#!/bin/sh
# Entry point of the `backup` container (VPS spec §3): installs the sqlite3 CLI, then runs
# backup-once.sh every day at 03:00 in the VPS's time zone (busybox crond; /etc/localtime is
# mounted from the host). Job output goes to the container log.
set -eu
apk add --no-cache sqlite >/dev/null
echo "0 3 * * * /bin/sh /backup/backup-once.sh >/proc/1/fd/1 2>/proc/1/fd/2" > /etc/crontabs/root
echo "backup: scheduled daily at 03:00 $(date +%Z)"
exec crond -f -l 8
