#!/bin/sh
# One backup of the relay database to /backups/relay-<YYYY-MM-DD>.db, keeping the KEEP newest.
# Uses SQLite's online backup, so it is consistent while the relay keeps writing. /data is mounted
# read-only: that works while the relay runs (it holds the WAL files open); while the relay is
# stopped the read fails, nothing is written, and nothing is lost either (a stopped relay changes
# nothing) — the next day's run tries again. `umask 077` makes every file this script writes 0600
# (the database holds user emails and password hashes); each finished backup is then handed to the
# owner of the backups folder (the deploy user, since this container runs as root), so that user can
# copy it off the VPS without sudo while nobody else can read it. Overridable for tests: DATA_DB,
# BACKUP_DIR, KEEP, BACKUP_DATE.
set -eu
umask 077
db="${DATA_DB:-/data/relay.db}"
dir="${BACKUP_DIR:-/backups}"
keep="${KEEP:-14}"
day="${BACKUP_DATE:-$(date +%F)}"
target="$dir/relay-$day.db"
tmp="$dir/.relay-$day.db.tmp"

rm -f "$tmp"
# sqlite3 would silently create (and back up) an empty database if the file were missing.
if [ ! -s "$db" ]; then
  echo "backup: skipped $day: $db is missing or empty" >&2
  exit 1
fi
if ! sqlite3 "$db" ".backup '$tmp'" 2>/dev/null; then
  rm -f "$tmp"
  echo "backup: skipped $day: cannot read $db (is the relay running?)" >&2
  exit 1
fi
if [ "$(sqlite3 "$tmp" 'PRAGMA integrity_check;')" != "ok" ]; then
  rm -f "$tmp"
  echo "backup: skipped $day: the copy failed its integrity check" >&2
  exit 1
fi
mv "$tmp" "$target"
owner="$(ls -nd "$dir" | awk '{print $3 ":" $4}')"
if ! chown "$owner" "$target" 2>/dev/null; then
  echo "backup: could not hand $target to the owner of $dir ($owner); it stays root's" >&2
fi
echo "backup: wrote $target"

# Names sort by date: keep the KEEP newest, delete the rest.
ls -1 "$dir"/relay-*.db 2>/dev/null | sort -r | tail -n "+$((keep + 1))" | while read -r old; do
  rm -f "$old"
  echo "backup: removed $old"
done
