---
name: run-moniz
description: Build, run, and drive Moniz, the Flutter wealth/zakat tracker. Use when asked to start Moniz, launch or run the app, build it, run its tests, take a screenshot of its UI, or tap/type/interact with the running app.
---

Moniz is a Flutter app (Riverpod + Hive) that runs as a **macOS desktop app**.
Agents drive it with `.claude/skills/run-moniz/driver.dart` — a Flutter Driver
REPL that launches the app, taps widgets, types text, reads on-screen strings,
and writes PNG screenshots. Feed it commands on stdin.

All paths below are relative to the repo root.

## Prerequisites

Flutter on the `stable` channel plus Xcode command-line tools. Verified against:

```bash
flutter --version   # Flutter 3.41.9 • Dart 3.11.5
flutter devices     # must list "macOS (desktop) • macos"
```

## Setup

`flutter_driver` is in `dev_dependencies` **solely** to power this skill's
driver — it is not used by the app or the test suite. Restore it if a rebase
drops it.

```bash
flutter pub get
```

No env vars or API keys are needed. `.env.json` is not read at launch, and the
gold/silver prices come from Gold API's public endpoints over the network.

## Build

No separate build step — the driver builds on launch. To pre-warm the (slow,
several-minute) first macOS build:

```bash
flutter build macos --debug
```

## Run (agent path)

One command launches the app, connects the driver, runs your commands, and
shuts everything down cleanly:

```bash
dart run .claude/skills/run-moniz/driver.dart -d macos <<'EOF'
tap key:zakat_nav
screenshot cold-01-zakat
tap key:about_nav
screenshot cold-02-about
quit
EOF
```

Output is one line per command — `OK <result>` or `ERR <reason>` — after a
`READY <vm-service-uri>` line. Driver chatter goes to stderr; redirect it with
`2>/dev/null` to get a clean transcript.

Screenshots land in `build/moniz-shots/` (gitignored). **Open them** — a
stale-frame bug on macOS produces byte-identical PNGs, see Gotchas.

### Attaching to an already-running app

Relaunching costs ~30s, so keep one app up and re-attach for each batch. Start
it once in the background, grab the URI from the log, then attach:

```bash
nohup flutter run -d macos -t .claude/skills/run-moniz/driver_entry.dart --debug > /tmp/moniz_run.log 2>&1 &
URI=$(grep -o 'http://127.0.0.1:[0-9]*/[^ ]*' /tmp/moniz_run.log | head -1); echo "URI=$URI"
```

```bash
dart run .claude/skills/run-moniz/driver.dart --vm-service "$URI" <<'EOF'
strings
quit
EOF
```

Always quote the URI — it contains `=` and a trailing `/`, and zsh chokes on it
bare.

### Driver commands

| command | what it does |
|---|---|
| `screenshot <name>` | PNG to `build/moniz-shots/<name>.png` (or a literal path if it contains `/`) |
| `strings` | every string in the render tree, deduped and sorted — **the way to see what's on screen** |
| `tap <finder>` | taps; runs unsynchronized so the animated UI can't wedge it |
| `enter <text>` | types into the focused field (`tap` the field first) |
| `waitfor <finder>` / `waitgone <finder>` | wait for a widget to appear/disappear |
| `exists <finder>` | `yes` / `no` (3s probe) |
| `text <finder>` | reads a real `Text` widget — usually fails here, see Gotchas |
| `scroll <finder> <dx> <dy>` | scrollable keys are `dashboard_scroll`, `zakat_scroll`, `settings_scroll`, `about_scroll`, `notifications_scroll` |
| `rendertree [path]` | full dump to a file (multi-MB) — grep it |
| `focus` | force the macOS window to the front |
| `reload` / `restart` | hot reload / hot restart (spawned mode only) |
| `quit` | close the driver and terminate the app |

Finders are `key:<value>`, `text:<value>`, `tooltip:<value>`, `type:<Widget>`.
**Prefer `key:`** — the app keys nearly everything. List them with:

```bash
grep -rn "Key('" lib/ | sed "s/.*Key('\([^']*\)').*/\1/" | sort -u
```

Useful ones: `dashboard_nav`, `zakat_nav`, `settings_nav`,
`about_nav`, `open_notifications`, `close_notifications`, `add_asset_button`,
`asset_amount_field`, `asset_save_button`, `back_asset_form`,
`refresh_metal_prices`, `theme_mode_toggle`, `wealth_hero_total`.

### Verified end-to-end flow

This exact sequence tapped through to the Add-asset form, typed an amount, and
backed out without saving:

```bash
dart run .claude/skills/run-moniz/driver.dart --vm-service "$URI" 2>/dev/null <<'EOF'
tap key:dashboard_nav
scroll key:dashboard_scroll 0 -700
tap key:add_asset_button
waitfor key:asset_amount_field
tap key:asset_amount_field
enter 12.5
screenshot 21-asset-form
tap key:back_asset_form
waitgone key:asset_amount_field
quit
EOF
```

## Run (human path)

```bash
flutter run -d macos
```

A desktop window opens; `q` in the terminal quits, `r` hot-reloads. This path
has no driver extension, so `driver.dart` cannot attach to it — use
`driver_entry.dart` (above) if you want to drive it.

## Test

```bash
flutter test
```

70 tests, all passing. `Metal price refresh failed: Unavailable in widget test.`
is expected noise, not a failure — the widget tests stub out the network.

## Gotchas

- **An unfocused macOS window freezes the app.** `flutter run -d macos` logs
  `Failed to foreground app; open returned 1` and leaves the window in the
  background. macOS then stops driving frames, so every `tap` times out after
  20s and every screenshot is **byte-identical** to the last rendered frame —
  four different screens, one md5. `driver.dart` works around it by running
  `osascript … set frontmost` on connect and before every screenshot. If shots
  still repeat, run `focus` explicitly. **Always `md5` or open your PNGs** rather
  than trusting `OK`; a tap that silently did nothing still reports `OK`.
- **Driving the app mutates the real portfolio.** There is no fixture mode —
  the driver opens the developer's actual Hive boxes in
  `~/Library/Containers/com.example.moniz/`. Don't tap `asset_save_button` or
  `mark_zakat_paid` unless you mean to write real data; back out of forms with
  `back_asset_form`.
- **`text:` finders collide.** `tap text:Settings` fails with
  `Found 2 widgets with text "Settings"` — the nav label and the page heading.
  Flutter Driver demands exactly one match. Use `key:` finders.
- **`text <finder>` mostly doesn't work.** The UI wraps text in custom
  `KineticText`/`KineticNumber` widgets, and `getText` rejects them:
  `Type KineticNumber is currently not supported by getText`. Use `strings`.
- **`strings` and `rendertree` include offstage pages.** The bottom nav keeps
  other tabs in the tree, so About/Zakat/Settings text shows up even while
  you're on the dashboard. Confirm what's actually visible with a screenshot.
- **If a PIN was set, the app boots to a lock screen.** `AppLockGate` wraps the
  whole app. `strings` will show the unlock UI instead of the dashboard; unlock
  with `tap key:app_unlock_pin`, `enter <pin>`, `tap key:app_unlock_submit`.
- **`getWidgetDiagnostics` hangs**, unsynchronized or not, so the driver
  deliberately has no `diagnostics` command. Don't add one back; use `strings`.
- **macOS has no `timeout`.** Don't wrap the driver in it; every driver command
  is already bounded at 20s and the launch wait at 10 minutes.
- **`quit` is required.** Without it the app and `flutter run` outlive the
  driver. To clean up strays:
  `pkill -f "flutter_tools.snapshot run -d macos"; pkill -f "moniz.app/Contents/MacOS/moniz"`

## Troubleshooting

- **`ERR timeout after 20s: tap …`** — the window lost focus. Run `focus`, or
  check nothing is covering it. This is the same freeze described above.
- **`ERR DriverError: … Found 2 widgets with text "X"`** — ambiguous finder;
  switch to `key:`.
- **`ERR … Type KineticNumber is currently not supported by getText`** —
  use `strings` instead of `text`.
- **`StateError: flutter run exited early`** — read `/tmp/moniz_run.log`, or
  drop `2>/dev/null` to see the `[app]`-prefixed passthrough of `flutter run`.
- **`Target file "…driver_entry.dart" not found`** — you're not at the repo
  root. The `-t` path is relative to the Flutter project directory.
- **`no matches found:` from zsh** — quote the VM Service URI; it contains `=`.
