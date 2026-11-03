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
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Постоянный сертификат нужен, чтобы «Мониторинг ввода» не слетал после пересборки (см. CLAUDE.md).
# Нет сертификата — ad-hoc, как раньше.
IDENTITY="${MACTWEAKS_SIGN_IDENTITY:-Mac Tweaks Dev}"
if security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "Подпись: $IDENTITY"
else
  codesign --force --sign - "$APP"
  echo "Подпись: ad-hoc (сертификата «$IDENTITY» нет — разрешения слетят после пересборки, см. CLAUDE.md)"
fi
echo "Собрано: $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/MacTweaks.app
  cp -R "$APP" ~/Applications/
  echo "Установлено: ~/Applications/MacTweaks.app"
fi
