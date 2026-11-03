#!/bin/bash
# Собирает MacTweaks.app в ./dist.
#   --install  копирует в ~/Applications и перезапускает. Только из основной папки на ветке master:
#              установленная версия должна быть одна для всех сессий (см. CLAUDE.md, «Как ведётся разработка»).
#   --run      закрывает установленную копию и запускает dist/MacTweaks.app — для проверки ветки функции.
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
  echo "Подпись: ad-hoc (сертификата «${IDENTITY}» нет — разрешения слетят после пересборки, см. CLAUDE.md)"
fi
echo "Собрано: $APP"

case "${1:-}" in
  --install)
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" != "master" || "$(git rev-parse --git-dir)" != ".git" ]]; then
      echo "Отказ: --install только из ~/Documents/claude/mac-tweaks на master (сейчас: $BRANCH, $(pwd))." >&2
      echo "Для проверки ветки используйте ./build.sh --run, в ~/Applications ставит главная сессия после вливания." >&2
      exit 1
    fi
    pkill -x MacTweaks || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/MacTweaks.app
    cp -R "$APP" ~/Applications/
    echo "Установлено: ~/Applications/MacTweaks.app ($(git rev-parse --short HEAD))"
    open ~/Applications/MacTweaks.app
    ;;
  --run)
    pkill -x MacTweaks || true
    sleep 1
    open "$APP"
    echo "Запущено из $(pwd)/$APP. Вернуть общую версию: open ~/Applications/MacTweaks.app"
    ;;
esac
