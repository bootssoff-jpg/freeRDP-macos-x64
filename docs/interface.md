# Interface and languages / Интерфейс и языки

## English

The application uses `Resources/en.lproj/Localizable.strings` and
`Resources/ru.lproj/Localizable.strings`. Both directories are copied into the
app bundle. Swift's `L` and Objective-C's `RDPMacLocalizedString` resolve strings
through the same language bundle, including connection errors and diagnostics.
Russian text is the stable lookup key; missing keys safely fall back to it.

By default, a Russian system language selects Russian; other languages select
English. The application menu offers System language, English and Русский.
The `RDPMacLanguage` preference takes effect on the next launch. No running
session is restarted and no remote keyboard layout is changed by this setting.
`RDPMAC_LANGUAGE=en|ru` is a process-only override used by tests and previews.

Formatted strings retain the same placeholders in both languages. Test all
languages when adding or editing a key. Preserve user-provided profile names,
hosts, account names and clipboard content without translation.

Advanced settings are collapsed for a standard profile. A profile that enables
legacy security opens the section so those choices are visible. Editing from
the manager never automatically starts a connection. Searching reveals matching
profiles even when their group was collapsed.

**Duplicate connection** (manager context menu, the “Дублировать” button, or
`⌘⇧D` while the manager is frontmost) opens the editor with an unsaved copy: new
identity, the same host/group/settings and the same account record. Changing the
address keeps the saved password because the account record owns it. Nothing is
written until “Save copy”, so cancelling creates no profile and no Keychain item.

The **account directory** (“Справочник…” next to “Учётная запись”) stores title,
user name and domain only; passwords stay in the Keychain under
`credential/<uuid>`. One record can be used by several connections, so changing
its password affects all of them (the editor says so). Deleting a record keeps
its connections, which then keep only the user name and domain. Switching the
account in the form always clears the password field, so a previous user's
password is never reused. Directory edits never touch a running session: each
session received its own copy of the credentials when it started.

A **resolution preset** belongs to the profile: follow the window, 1024×768,
1280×720, 1600×900, 1920×1080, 2560×1440 or a custom size in pixels. Custom
sizes must stay within 640×480 … 4096×2560 and are rounded down to even values;
the form explains a rejected size and does not start the connection. Profiles
saved by 1.0.x with a fixed size keep it after the upgrade. Only the window
preset follows window changes; a fixed preset just scales the image.

The **Retina** switch means two different things, which the form states
explicitly: in window mode the remote size uses the display's backing scale, and
for fixed presets it asks Windows for 200 % DPI scaling (a server may ignore it,
which is visible immediately and not reported as success).

**Quality** is a per-profile preset: Normal, Slow internet or Custom. Custom
exposes wallpaper, themes, animations, window-drag contents, desktop
composition, font smoothing, 16-bit colour and RDP6 compression levels; changing
any flag switches the preset to Custom instead of pretending a preset still
applies. The values travel in the Client Info PDU, so they take effect on the
next connection. The slow preset also starts from 1280 × 720 without Retina
(the resolution popup changes visibly) and sends fewer DisplayControl resizes.

The **session toolbar** can be hidden with View → Show session toolbar (⌘⇧T) or
by the toolbar toggle. The remote desktop takes the whole window; in window mode
it follows the new size through DisplayControl, while fixed presets only
relayout. When the toolbar is hidden and a session fails, the window title shows
`host:port — ошибка` because the inline status line is gone. The choice is
remembered for new windows; full screen always hides the toolbar.

A clipboard response timeout offers explicit reconnection. The previous request
is retained until its response arrives because CLIPRDR responses have no request
ID. Do not clear it merely to make the UI appear recovered.

## Русский

Языковые ресурсы находятся в `en.lproj` и `ru.lproj`; интерфейс Swift и ошибки
Objective-C используют один механизм выбора. По умолчанию русский язык системы
выбирает русский интерфейс, остальные языки — английский. Ручной выбор в меню
применяется после перезапуска и не затрагивает раскладку Windows.

Пользовательские имена, адреса, учётные записи и содержимое буфера не переводятся.
Параметры формата в переводах должны совпадать. Формы проверяются в обоих языках.

Дополнительные настройки стандартного профиля свёрнуты. При выборе устаревшей
безопасности они раскрываются. Редактирование из менеджера не запускает сессию.
Поиск показывает совпадения даже в свёрнутой группе.

После тайм-аута канал восстанавливается через явное переподключение. Нельзя
сбрасывать ожидание ответа без учёта запоздалых ответов CLIPRDR.

**Разрешение** хранится в профиле: как в окне, 1024×768, 1280×720, 1600×900,
1920×1080, 2560×1440 или свой размер в пикселях. Свой размер должен быть в
пределах 640×480 … 4096×2560 и округляется вниз до чётного; форма объясняет
отказ и не начинает подключение. Профили 1.0.x с фиксированным размером
сохраняют его после обновления. За окном следует только режим «Как в окне»,
фиксированный размер просто масштабирует изображение.

Переключатель **Retina** означает разное, и форма говорит об этом прямо: в
режиме «Как в окне» размер считается по плотности дисплея, а для фиксированных
размеров в Windows запрашивается масштаб 200 % (сервер может его
проигнорировать — это видно сразу и не выдаётся за успех).

**Качество** — пресет профиля: «Обычное», «Медленный интернет» или
«Пользовательское». В пользовательском доступны обои, темы, анимации,
содержимое при перетаскивании, композиция рабочего стола, сглаживание шрифтов,
16 бит и уровни сжатия RDP6; изменение любого флага переводит пресет в
«Пользовательское», а не делает вид, что пресет ещё действует. Значения
передаются в Client Info PDU и применяются к следующему подключению.
«Медленный интернет» дополнительно начинает с 1280 × 720 без Retina (это видно
в списке разрешений) и реже отправляет запросы изменения размера.

**Панель сеанса** скрывается через «Вид → Показывать панель сеанса» (⌘⇧T) или
кнопку на панели. Рабочий стол занимает всё окно; в режиме «Как в окне» он
следует за новым размером через DisplayControl, фиксированные размеры только
пересчитывают раскладку. Если панель скрыта и сеанс завершился ошибкой, заголовок
окна показывает `host:port — ошибка`, потому что строки состояния нет. Выбор
запоминается для новых окон; полноэкранный режим всегда скрывает панель.

## Preview images

After building the app, run `./scripts/render_previews.sh` to render the actual
AppKit views offscreen in EN and RU. The development-only tool injects reserved
`.invalid` demo profiles in memory. It does not create network connections or
store demo profiles/passwords. Preview images show the interface, not working
remote sessions. The renderer is not included in the shipped application.

## Performance verification

Implemented changes:

- Inactive clipboard sessions stop their 0.4-second polling timer; returning to
  the session restarts it.
- Fully occluded session windows do not schedule drawing for frame updates;
  becoming visible requests a fresh draw. Network processing remains active.
- Log display updates are batched at 150 ms, append new text when possible,
  and preserve scroll position when the reader is away from the end.
- Automatic graphics switching is allowed on compatible dual-GPU Macs.

No speed or battery-life improvement is claimed without measurements. Before
changing the framebuffer architecture, compare Instruments Time Profiler,
Allocations and Energy Log for 1/5/10 real sessions: idle, typing, scrolling,
resize and background windows. Record CPU, memory, wakeups and input latency.
The current renderer still copies a complete frame on each displayed update;
partial copies remain a follow-up requiring profiling and concurrency tests.
