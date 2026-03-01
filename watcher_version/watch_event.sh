#!/system/bin/sh

MODDIR="${0%/*}"
TMP_ROOT="/data/local/tmp/rustore-apk-autowatch"
EVENT_LOCK="$TMP_ROOT/event_worker.lock"

mkdir -p "$TMP_ROOT"

# Coalesce event bursts into a single delayed installer run.
if ! mkdir "$EVENT_LOCK" 2>/dev/null; then
  exit 0
fi

(
  # Give downloads a moment to finish writing/renaming ZIP.
  sleep 8
  /system/bin/sh "$MODDIR/installer.sh"
  rm -rf "$EVENT_LOCK"
) >/dev/null 2>&1 &
