#!/usr/bin/env bash
# Correr UNA vez, en la carpeta del proyecto, DESPUÉS de `flutter create .`
# Agrega permisos de cámara/fotos/notificaciones y fija iOS 15.5 (requerido por ML Kit).
set -e
cd "$(dirname "$0")/.."

M=android/app/src/main/AndroidManifest.xml
if [ -f "$M" ] && ! grep -q "android.permission.CAMERA" "$M"; then
  python3 - "$M" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
perms = '''    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
'''
s = s.replace('<application', perms + '    <application', 1)
open(p, 'w', encoding='utf-8').write(s)
PY
  echo "Android: permisos agregados"
fi

PL=ios/Runner/Info.plist
if [ -f "$PL" ] && [ -x /usr/libexec/PlistBuddy ]; then
  add() { /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PL" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PL"; }
  add NSCameraUsageDescription "Se usa la cámara para escanear QR, DNI y patentes, y sacar fotos de perfil."
  add NSPhotoLibraryUsageDescription "Se usa la galería para elegir la foto de perfil."
  echo "iOS: Info.plist actualizado"
fi

PF=ios/Podfile
if [ -f "$PF" ]; then
  sed -i.bak -E "s/^# *platform :ios.*/platform :ios, '15.5'/" "$PF" && rm -f "$PF.bak"
  grep -q "platform :ios, '15.5'" "$PF" && echo "iOS: Podfile en 15.5" || echo "Revisá ios/Podfile: poné platform :ios, '15.5'"
fi
