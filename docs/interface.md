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
