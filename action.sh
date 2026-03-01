#!/system/bin/sh

MODDIR="${0%/*}"

if [ -x "$MODDIR/installer.sh" ]; then
  exec "$MODDIR/installer.sh"
fi

exec /system/bin/sh "$MODDIR/installer.sh"
