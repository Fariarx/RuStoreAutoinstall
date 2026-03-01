SKIPUNZIP=0

set_permissions() {
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/service.sh" 0 0 0755
  set_perm "$MODPATH/watcher.sh" 0 0 0755
  set_perm "$MODPATH/watch_event.sh" 0 0 0755
  set_perm "$MODPATH/installer.sh" 0 0 0755
}
