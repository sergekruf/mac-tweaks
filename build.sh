#!/bin/bash
# Собирает MacTweaks.app в ./dist. С флагом --install копирует в ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=dist/MacTweaks.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MacTweaks "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Собрано: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/MacTweaks.app
  cp -R "$APP" ~/Applications/
  echo "Установлено: ~/Applications/MacTweaks.app"
fi
