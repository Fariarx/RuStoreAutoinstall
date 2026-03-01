#!/system/bin/sh

MODDIR="${0%/*}"

/system/bin/sh "$MODDIR/watcher.sh" >/dev/null 2>&1 &
