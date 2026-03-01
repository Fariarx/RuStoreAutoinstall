#!/system/bin/sh

TAG="RuStoreAutoInstall"
SRC_DIR="/data/data/ru.vk.store/files/apkStorage"
TMP_ROOT="/data/local/tmp/rustore-apk-autoinstall"
LOG_FILE="$TMP_ROOT/install.log"
ZIP_LIST="$TMP_ROOT/zip_list.txt"

mkdir -p "$TMP_ROOT"

log_msg() {
  msg="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" >> "$LOG_FILE"
  echo "$msg"
  log -t "$TAG" "$msg"
}

get_busybox() {
  magisk_path="$(magisk --path 2>/dev/null)"
  if [ -n "$magisk_path" ] && [ -x "$magisk_path/busybox" ]; then
    echo "$magisk_path/busybox"
    return 0
  fi

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

  # If archive path is installable directly (for example, file with wrong extension), use it.
  if install_single_apk "$zip_path"; then
    rm -f "$zip_path"
    log_msg "Installed directly and removed: $zip_path"
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
      else
        log_msg "Failed to install APK: $apk"
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
  run_once
}

main
