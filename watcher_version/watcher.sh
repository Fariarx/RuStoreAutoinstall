#!/system/bin/sh

TAG="RuStoreAutoWatch"
SRC_DIR="/data/data/ru.vk.store/files/apkStorage"
TMP_ROOT="/data/local/tmp/rustore-apk-autowatch"
LOG_FILE="$TMP_ROOT/watcher.log"
PID_FILE="$TMP_ROOT/watcher.pid"
MODDIR="${0%/*}"
POLL_INTERVAL=20

mkdir -p "$TMP_ROOT"

log_msg() {
  msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG_FILE"
  log -t "$TAG" "$msg"
}

get_busybox() {
  if command -v magisk >/dev/null 2>&1; then
    magisk_path="$(magisk --path 2>/dev/null)"
    if [ -n "$magisk_path" ] && [ -x "$magisk_path/busybox" ]; then
      echo "$magisk_path/busybox"
      return 0
    fi
  fi

  for bb in \
    /data/adb/magisk/busybox \
    /sbin/.magisk/busybox \
    /debug_ramdisk/.magisk/busybox \
    /data/adb/ksu/bin/busybox \
    /system/xbin/busybox \
    /system/bin/busybox
  do
    if [ -x "$bb" ]; then
      echo "$bb"
      return 0
    fi
  done

  bb_path="$(command -v busybox 2>/dev/null)"
  if [ -n "$bb_path" ]; then
    echo "$bb_path"
    return 0
  fi

  return 1
}

cleanup() {
  if [ -n "$inotify_pid" ] && kill -0 "$inotify_pid" >/dev/null 2>&1; then
    kill "$inotify_pid" >/dev/null 2>&1
    wait "$inotify_pid" 2>/dev/null
  fi
  rm -f "$PID_FILE"
  log_msg "Watcher stopped"
}

build_dir_list() {
  out_file="$1"
  find "$SRC_DIR" -type d 2>/dev/null | sort > "$out_file"
}

dir_list_sig() {
  list_file="$1"
  if [ ! -s "$list_file" ]; then
    echo "0:0"
    return
  fi
  if command -v cksum >/dev/null 2>&1; then
    cksum "$list_file" 2>/dev/null | awk '{print $1 ":" $2}'
  else
    line_count="$(wc -l < "$list_file" 2>/dev/null | tr -d ' ')"
    echo "lines:$line_count"
  fi
}

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null)"
  if [ -n "$old_pid" ] && kill -0 "$old_pid" >/dev/null 2>&1; then
    log_msg "Watcher already running with PID $old_pid"
    exit 0
  fi
fi

echo $$ > "$PID_FILE"
trap cleanup EXIT INT TERM

BB="$(get_busybox 2>/dev/null)"

USE_BB_INOTIFY=0
USE_SYS_INOTIFY=0
if [ -n "$BB" ] && "$BB" inotifyd --help >/dev/null 2>&1; then
  USE_BB_INOTIFY=1
elif command -v inotifyd >/dev/null 2>&1; then
  USE_SYS_INOTIFY=1
else
  log_msg "inotifyd is unavailable (BusyBox/System), busybox path='$BB'"
  exit 1
fi

if [ "$USE_BB_INOTIFY" -eq 1 ]; then
  log_msg "Watcher started (using BusyBox inotifyd: $BB)"
else
  log_msg "Watcher started (using system inotifyd)"
fi

while true; do
  if [ ! -d "$SRC_DIR" ]; then
    log_msg "Source directory not found: $SRC_DIR"
    sleep 15
    continue
  fi

  /system/bin/sh "$MODDIR/installer.sh"

  DIR_LIST="$TMP_ROOT/watch_dirs.txt"
  build_dir_list "$DIR_LIST"

  if [ ! -s "$DIR_LIST" ]; then
    log_msg "No directories to watch under: $SRC_DIR"
    sleep 15
    continue
  fi

  set --
  dir_count=0
  current_sig="$(dir_list_sig "$DIR_LIST")"

  while IFS= read -r dir_path; do
    [ -n "$dir_path" ] || continue
    set -- "$@" "$dir_path:nmywdDM"
    dir_count=$((dir_count + 1))
  done < "$DIR_LIST"

  log_msg "Starting inotifyd for $dir_count directories (sig=$current_sig)"
  if [ "$USE_BB_INOTIFY" -eq 1 ]; then
    "$BB" inotifyd "$MODDIR/watch_event.sh" "$@" >> "$LOG_FILE" 2>&1 &
  else
    inotifyd "$MODDIR/watch_event.sh" "$@" >> "$LOG_FILE" 2>&1 &
  fi
  inotify_pid=$!

  while kill -0 "$inotify_pid" >/dev/null 2>&1; do
    sleep "$POLL_INTERVAL"
    /system/bin/sh "$MODDIR/installer.sh"

    NEW_LIST="$TMP_ROOT/watch_dirs.new"
    build_dir_list "$NEW_LIST"
    new_sig="$(dir_list_sig "$NEW_LIST")"

    if [ "$new_sig" != "$current_sig" ]; then
      new_count="$(wc -l < "$NEW_LIST" 2>/dev/null | tr -d ' ')"
      if [ -z "$new_count" ]; then
        new_count=0
      fi
      log_msg "Directory set changed (sig $current_sig -> $new_sig, count $dir_count -> $new_count), restarting inotifyd"
      kill "$inotify_pid" >/dev/null 2>&1
      wait "$inotify_pid" 2>/dev/null
      inotify_pid=""
      mv -f "$NEW_LIST" "$DIR_LIST"
      break
    fi
    rm -f "$NEW_LIST"
  done

  if [ -n "$inotify_pid" ]; then
    wait "$inotify_pid" 2>/dev/null
    inotify_pid=""
  fi

  sleep 2
done
