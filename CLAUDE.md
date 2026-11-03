# Mac Tweaks

Нативное приложение для macOS (SwiftUI), которое собирает базовые настройки системы
в одном месте — чтобы быстро настроить новый Mac или чужой.

## Устройство

- Swift Package, без Xcode-проекта. macOS 14+, не sandbox (пишет глобальные defaults, перезапускает системные процессы).
- `Sources/MacTweaks/App.swift` — точка входа и `enum TweakModule`: каждый кейс — раздел в боковом меню.
- `Sources/MacTweaks/AppDelegate.swift` — запуск без SwiftUI `App`: главное окно (`NSWindow`, закрытие не завершает приложение), меню приложения, значок в строке меню и его меню. `KeepAwake.swift` — режим «не засыпать» (IOPMAssertion), `WrenchGlyph.swift` — значок строки меню из геометрии `icon.swift`.
- `Sources/MacTweaks/Modules/` — по одному файлу на модуль: модель (`ObservableObject`) + вью.
- `Sources/MacTweaks/Shell.swift` — `GlobalDefaults` (чтение/запись `-globalDomain` через CFPreferences, уровни any/currentHost) и `Shell` (запуск процессов, `killall`).
- `Resources/Info.plist`, `Resources/AppIcon.icns` — копируются в бандл скриптом сборки.
- `design/icon/icon.swift` — исходник иконки (вектор, сетка Apple 824/1024). Правка: поменять числа → `swift icon.swift .` → пересобрать `.icns` через `sips` + `iconutil` из `icon-v1.png`.

## Сборка

```bash
./build.sh            # собирает dist/MacTweaks.app (ad-hoc подпись)
./build.sh --install  # + копирует в ~/Applications
```

## Как добавить модуль

1. Файл `Modules/<Name>View.swift`: модель и вью, оформление — `Form` + `.formStyle(.grouped)`, как в `MenuBarSpacingView`.
2. Кейс в `TweakModule` (title, SF Symbol, view).
3. Обязательно: показывать текущее значение из системы, кнопки «Применить» и «Сбросить к системным» (сброс = удаление ключа, а не запись «дефолтного» числа).
4. Если настройка требует перезапуска процесса (Dock, Finder, ControlCenter) — делать это в «Применить» и писать об этом в статусе.

## Правила

- Ничего в системе не менять при запуске приложения или при движении ползунка — только по явной кнопке.
- Перед правками и после проверки — запись в `docs/JOURNAL.md`: что делали, что сработало, что нет и почему. Особенно поведение, отличающееся между версиями macOS.
- Статусы функций — в `docs/ROADMAP.md`.
- Тексты интерфейса — на русском.

## Как ведётся разработка

- Главная сессия ведёт `docs/ROADMAP.md` и `docs/JOURNAL.md`, запускает сессии под функции и вливает результат в `main`.
- Каждая функция — отдельная сессия в своём worktree и ветке `feature/<name>`.
- Сессия функции в конце: собирает `./build.sh`, дописывает запись в `docs/JOURNAL.md`, меняет статус в `docs/ROADMAP.md`, коммитит в свою ветку.
