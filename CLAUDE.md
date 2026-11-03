# Mac Tweaks

Нативное приложение для macOS (SwiftUI), которое собирает базовые настройки системы
в одном месте — чтобы быстро настроить новый Mac или чужой.

## Устройство

- Swift Package, без Xcode-проекта. macOS 14+, не sandbox (пишет глобальные defaults, перезапускает системные процессы).
- `Sources/MacTweaks/App.swift` — точка входа и `enum TweakModule`: каждый кейс — раздел в боковом меню.
- `Sources/MacTweaks/AppDelegate.swift` — запуск без SwiftUI `App`: главное окно (`NSWindow`, закрытие не завершает приложение), меню приложения, значок в строке меню и его меню. `KeepAwake.swift` — режим «не засыпать» (IOPMAssertion), `WrenchGlyph.swift` — значок строки меню из геометрии `icon.swift`.
- `Sources/MacTweaks/Modules/` — по одному файлу на модуль: модель (`ObservableObject`) + вью.
- `Sources/MacTweaks/LayoutSwitcher.swift` — смена языка по сочетанию: listen-only CGEventTap + `TISSelectInputSource`.
  Логика «нажали-отпустили без других клавиш» — в таргете `Sources/KeyChord` (без зависимостей от системы), тесты — `Tests/KeyChordTests`.
- `Sources/MacTweaks/EventTap.swift` — общий `EventTap` (создание, повторное включение, слежение за разрешением) и `EventTapPermission`
  (listen-only → «Мониторинг ввода», активный tap → «Универсальный доступ»); `RunningApps` — какие приложения запущены. Новый перехват — через него.
- `Sources/MacTweaks/MouseScroller.swift` — колесо мыши: активный tap на `scrollWheel`. Решение «что сделать с дельтами» — в таргете
  `Sources/ScrollWheel` (без зависимостей от системы), тесты — `Tests/ScrollWheelTests`. Порядок записи полей: строки → FixedPt → Point (см. журнал).
- `Sources/MacTweaks/Shell.swift` — `GlobalDefaults` (чтение/запись `-globalDomain` через CFPreferences, уровни any/currentHost) и `Shell` (запуск процессов, `killall`).
- `Resources/Info.plist`, `Resources/AppIcon.icns` — копируются в бандл скриптом сборки.
- `design/icon/icon.swift` — исходник иконки (вектор, сетка Apple 824/1024). Правка: поменять числа → `swift icon.swift .` → пересобрать `.icns` через `sips` + `iconutil` из `icon-v1.png`.

## Сборка

```bash
./build.sh            # собирает dist/MacTweaks.app (ad-hoc подпись)
./build.sh --install  # + копирует в ~/Applications
swift test            # тесты KeyChord и ScrollWheel
```

### Подпись и разрешения «Мониторинг ввода» / «Универсальный доступ»

macOS (TCC) запоминает разрешение по designated requirement подписи. При ad-hoc подписи это `cdhash` — он меняется
с каждой сборкой, и разрешение слетает. Решение — постоянный самоподписанный сертификат:

1. Один раз: `./scripts/make-signing-cert.sh` — создаёт «Mac Tweaks Dev» в login keychain (openssl + `security import`).
   Доверие не нужно: codesign подписывает и недоверенным сертификатом. При первой подписи macOS может спросить доступ к ключу — «Разрешать всегда».
2. `./build.sh` сам находит сертификат (имя можно сменить через `MACTWEAKS_SIGN_IDENTITY`), без него — ad-hoc с предупреждением.
3. После перехода с ad-hoc на сертификат разрешение выдать заново один раз (старую запись Mac Tweaks в списке удалить «−»).
   Дальше пересборки его не сбрасывают. Проверка: `codesign -d -r- dist/MacTweaks.app` → `certificate leaf = H"…"`, не `cdhash`.

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
