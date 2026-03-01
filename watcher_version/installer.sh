#!/system/bin/sh

TAG="RuStoreAutoWatch"
SRC_DIR="/data/data/ru.vk.store/files/apkStorage"
TMP_ROOT="/data/local/tmp/rustore-apk-autowatch"
LOG_FILE="$TMP_ROOT/install.log"
ZIP_LIST="$TMP_ROOT/zip_list.txt"
NOTIFY_TAG="rustore_autowatch"
LOCK_DIR="$TMP_ROOT/installer.lock"

mkdir -p "$TMP_ROOT"

log_msg() {
  msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG_FILE"
  echo "$msg"
  log -t "$TAG" "$msg"
}

release_lock() {
  rm -rf "$LOCK_DIR"
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
    trap release_lock EXIT INT TERM
    return 0
  fi

  if [ -f "$LOCK_DIR/pid" ]; then
    lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" >/dev/null 2>&1; then
      log_msg "Installer already running (pid=$lock_pid), skip trigger"
      return 1
    fi
  fi

  rm -rf "$LOCK_DIR"
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
    trap release_lock EXIT INT TERM
    return 0
  fi

  log_msg "Failed to acquire installer lock"
  return 1
}

sanitize_text() {
  echo "$1" | tr '\n' ' ' | tr '\r' ' ' | sed 's/["`$\\]/_/g'
}

notify_popup() {
  title="$(sanitize_text "$1")"
  text="$(sanitize_text "$2")"

  if ! command -v cmd >/dev/null 2>&1; then
    return 1
  fi

  if command -v su >/dev/null 2>&1; then
    su 2000 -c "cmd notification post -S bigtext -t \"$title\" $NOTIFY_TAG \"$text\"" >/dev/null 2>&1 && return 0
    su -lp 2000 -c "cmd notification post -S bigtext -t \"$title\" $NOTIFY_TAG \"$text\"" >/dev/null 2>&1 && return 0
  fi

  cmd notification post --user 0 -S bigtext -t "$title" "$NOTIFY_TAG" "$text" >/dev/null 2>&1 && return 0
  cmd notification post -S bigtext -t "$title" "$NOTIFY_TAG" "$text" >/dev/null 2>&1 && return 0
  cmd notification post -t "$title" "$NOTIFY_TAG" "$text" >/dev/null 2>&1 && return 0
  cmd notification post "$NOTIFY_TAG" "$text" >/dev/null 2>&1 && return 0

  return 1
}

notify_apk_result() {
  apk_path="$1"
  result="$2"
  app_name="$(basename "$apk_path")"

  if [ "$result" = "ok" ]; then
    text="Installed: $app_name"
  else
    text="Failed: $app_name"
  fi

  if ! notify_popup "RuStore AutoWatch" "$text"; then
    log_msg "Notification failed: $text"
  fi
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

install_single_apk() {
  apk="$1"

  if pm install -r --user 0 "$apk" >/dev/null 2>&1; then
    return 0
  fi

  if cmd package install -r --user 0 "$apk" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

install_multiple_apk() {
  if pm install-multiple -r --user 0 "$@" >/dev/null 2>&1; then
    return 0
  fi

  if cmd package install-multiple -r --user 0 "$@" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

process_zip_file() {
  zip_path="$1"
  bb_path="$2"

  log_msg "Processing archive: $zip_path"

  if install_single_apk "$zip_path"; then
    rm -f "$zip_path"
    log_msg "Installed directly and removed: $zip_path"
    notify_apk_result "$zip_path" "ok"
    return
  fi

  safe_name="$(echo "$zip_path" | tr '/:' '__' | tr -cd '[:alnum:]_.-')"
  [ -n "$safe_name" ] || safe_name="archive"
  zip_tmp="$TMP_ROOT/$safe_name.$$"

  rm -rf "$zip_tmp"
  mkdir -p "$zip_tmp"

  if [ -n "$bb_path" ]; then
    "$bb_path" unzip -o "$zip_path" -d "$zip_tmp" >/dev/null 2>&1
  elif command -v unzip >/dev/null 2>&1; then
    unzip -o "$zip_path" -d "$zip_tmp" >/dev/null 2>&1
  else
    log_msg "No unzip tool available, skipping: $zip_path"
    rm -rf "$zip_tmp"
    return
  fi

  apk_list="$zip_tmp/apk_files.txt"
  find "$zip_tmp" -type f -name "*.[Aa][Pp][Kk]" > "$apk_list" 2>/dev/null

  if [ ! -s "$apk_list" ]; then
    log_msg "No APK found in archive: $zip_path"
    rm -rf "$zip_tmp"
    return
  fi

  installed_any=0
  installed_count=0
  apk_count=0
  multi_ok=0
  set --

  while IFS= read -r apk; do
    [ -n "$apk" ] || continue
    set -- "$@" "$apk"
    apk_count=$((apk_count + 1))
  done < "$apk_list"

  if [ "$apk_count" -gt 1 ]; then
    if install_multiple_apk "$@"; then
      installed_any=1
      installed_count="$apk_count"
      multi_ok=1
      log_msg "Installed split/multi APK set from: $zip_path"
      for apk in "$@"; do
        notify_apk_result "$apk" "ok"
      done
    else
      log_msg "Multi-APK install failed, trying one-by-one: $zip_path"
    fi
  fi

  if [ "$multi_ok" -eq 0 ]; then
    for apk in "$@"; do
      if install_single_apk "$apk"; then
        installed_any=1
        installed_count=$((installed_count + 1))
        log_msg "Installed APK: $apk"
        notify_apk_result "$apk" "ok"
      else
        log_msg "Failed to install APK: $apk"
        notify_apk_result "$apk" "fail"
      fi
    done
  fi

  if [ "$installed_count" -eq "$apk_count" ] && [ "$installed_any" -eq 1 ]; then
    rm -f "$zip_path"
    log_msg "Removed processed archive: $zip_path"
  else
    log_msg "Archive kept (installed $installed_count/$apk_count APK): $zip_path"
  fi

  rm -rf "$zip_tmp"
}

run_once() {
  if [ ! -d "$SRC_DIR" ]; then
    log_msg "Source directory not found: $SRC_DIR"
    return 0
  fi

  bb_path="$(get_busybox 2>/dev/null)"

  find "$SRC_DIR" -type f -name "*.[Zz][Ii][Pp]" > "$ZIP_LIST" 2>/dev/null

  if [ ! -s "$ZIP_LIST" ]; then
    log_msg "No ZIP archives found in: $SRC_DIR"
    return 0
  fi

  while IFS= read -r zip_path; do
    [ -n "$zip_path" ] || continue
    process_zip_file "$zip_path" "$bb_path"
  done < "$ZIP_LIST"

  rm -f "$ZIP_LIST"
  log_msg "Run completed."
  return 0
}

main() {
  if ! acquire_lock; then
    exit 0
  fi
  run_once
}

main
