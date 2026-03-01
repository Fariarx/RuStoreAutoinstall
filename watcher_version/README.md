# RuStore APK AutoWatch (Magisk Module)

Repository: https://github.com/Fariarx/RuStoreAutoinstall

This module watches:

`/data/data/ru.vk.store/files/apkStorage`

using `busybox inotifyd`, then installs or updates APK from new ZIP archives.

## Behavior

1. Monitors directory tree with `inotifyd`.
2. Starts automatically after boot via Magisk `service.sh`.
3. Performs initial scan at watcher start.
4. For each ZIP:
   - extracts APK,
   - installs (`pm install-multiple` then fallback to single `pm install -r`),
   - removes ZIP only if all APK from that ZIP were installed.
5. Sends system notifications (`Installed` / `Failed`) for each APK.
6. Runs periodic fallback scan every ~20 seconds (to avoid missed events).

## Logs

- Install log: `/data/local/tmp/rustore-apk-autowatch/install.log`
- Watcher log: `/data/local/tmp/rustore-apk-autowatch/watcher.log`

## Quick check if watcher fails

```sh
su -c '$(magisk --path)/busybox inotifyd --help'
su -c 'command -v inotifyd'
su -c 'ps -A | grep watcher.sh'
su -c tail -n 100 /data/local/tmp/rustore-apk-autowatch/watcher.log
```

## Build ZIP for Magisk app

```sh
zip -r RuStore-AutoWatch-Inotify-v1.0.0.zip module.prop installer.sh watcher.sh watch_event.sh service.sh customize.sh skip_mount README.md
```
