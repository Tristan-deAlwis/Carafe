# Carafe

A macOS menu bar app that reminds you to drink water through the day.

Carafe lives in the menu bar as a vector carafe outline — no Dock icon, no
window. Click it and a see-through carafe opens, with measuring-jug graduations
showing how much water you have left to drink today.

The carafe **drains**. It starts full at midnight with the day's goal and empties
as you log drinks, so the water level *is* the amount remaining.

---

## Install

```sh
brew tap tristan-dealwis/carafe
brew install --cask carafe
```

Or download the latest `.zip` from
[Releases](https://github.com/Tristan-deAlwis/Carafe/releases) and drag
`Carafe.app` to `/Applications`.

Requires macOS 14 (Sonoma) or later. Universal — Apple silicon and Intel.

### If macOS says Carafe is "damaged"

It isn't. Releases are not yet notarized by Apple, and Gatekeeper's message for
unsigned software is misleading. Clear the quarantine flag:

```sh
xattr -d com.apple.quarantine /Applications/Carafe.app
```

This goes away once the project has a Developer ID certificate.

---

## Using it

| | |
|---|---|
| **Log a glass** | Click the menu bar icon, then the **Log** button |
| **Other amounts** | The **⋯** menu beside it |
| **Undo** | The arrow button, which only affects today |
| **Fix a past day** | Click any bar in the history strip |
| **Settings** | The gear in the popover header |

Settings cover the daily goal, glass size, units (ml or US fl oz), reminder
interval, active hours, and launch at login.

Your last seven days appear as a bar strip under the carafe, with a streak count.
A day counts toward the streak when you meet its goal — and a day still in
progress never breaks it, so today's incomplete total is not held against you.

### Correcting a past day

Forgot to log a glass yesterday? Click any bar in the history strip to open that
day and set what you actually drank — type an exact figure, or step up and down
by your glass size. Days you never recorded at all can be filled in the same way;
the future can't be edited, since there is nothing to correct yet.

Each day keeps the goal that was in force when it was logged, so raising your
daily goal never retroactively breaks an old streak. Editing recomputes the
streak immediately, in either direction.

One deliberate trade-off: setting a day's total replaces that day's individual
entries with a single figure. Carafe has no intraday view, so the separate
timestamps aren't visible anywhere, and collapsing them keeps the displayed total
honest. Today's granular history still builds up normally through quick-add —
only an explicit edit collapses it.

### A note on reminders

macOS only delivers notifications from apps carrying a real code-signing
identity. Until Carafe is signed with a Developer ID, the system refuses to
register it — so Carafe detects this at launch and falls back to **marking its
menu bar icon** with a badge, plus a soft sound, when a reminder is due. Opening
the popover clears it.

Once signing is in place, the app moves to real notification banners — with
**Log a glass** and **Snooze** actions — automatically, with no setting to
change. The Settings panel tells you which route is currently active.

---

## Development

The project is generated from [`project.yml`](project.yml) by
[XcodeGen](https://github.com/yonaskolb/XcodeGen); `Carafe.xcodeproj` is not
committed.

```sh
./Scripts/bootstrap.sh   # installs XcodeGen if needed, generates the project
./Scripts/build.sh       # builds and launches
open Carafe.xcodeproj    # or work in Xcode
```

If you have both Xcode and the Command Line Tools installed, `xcodebuild` may
resolve to the wrong one. Every script sets `DEVELOPER_DIR` itself, so they work
regardless; to fix it globally:

```sh
sudo xcode-select -s /Applications/Xcode.app
```

### Tests

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme Carafe -destination 'platform=macOS' test
```

The model layer is pure and covered directly: day rollover, streak rules, unit
conversion, reminder slot maths, and corrupt-file handling.

Two suites write PNGs instead of asserting on pixels, because SwiftUI output
shifts between OS versions and image-comparison snapshots would be brittle:

```sh
# Inspect the artwork by eye
TEST_RUNNER_CARAFE_RENDER_DIR=/tmp/carafe-render \
  xcodebuild -scheme Carafe -destination 'platform=macOS' \
  -only-testing:CarafeTests/RenderSnapshotTests test

# Regenerate the app icon after changing CarafeShape or AppIconView
./Scripts/generate-icon.sh
```

### Layout

```
Sources/
├── CarafeApp.swift        @main, MenuBarExtra
├── AppDelegate.swift      midnight rollover, wake, notification actions
├── Model/                 HydrationStore, DayLog, DrinkEntry, UnitSystem
├── Shapes/                CarafeShape, WaterSurface
├── Views/                 popover, gauge, graduations, quick add, history, day editor, settings
├── Services/              MenuBarIcon, ReminderScheduler, LaunchAtLogin
└── Support/               HistoryStore (JSON persistence)
```

`CarafeShape` is the single source of truth for the silhouette — the menu bar
icon, the popup gauge, and the app icon are all rendered from it, so they cannot
drift apart.

Settings live in `UserDefaults`; history lives in
`~/Library/Application Support/Carafe/history.json`, pruned to the last 400 days.
The app is deliberately **not** sandboxed — it is distributed outside the App
Store, and the sandbox would only push that file into a container.

---

## Releasing

```sh
./Scripts/release.sh
```

Produces a universal, zipped `dist/Carafe-<version>.zip` and prints the SHA-256
for the cask. Signing and notarization are opt-in and skipped cleanly when
absent:

```sh
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="carafe" \
  ./Scripts/release.sh
```

Set the notary profile up once with:

```sh
xcrun notarytool store-credentials carafe \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
```

Pushing a `v*` tag runs [`release.yml`](.github/workflows/release.yml), which
does the same thing on CI and publishes a GitHub Release. It signs and notarizes
only if the repository secrets are present, and labels the release notes
accordingly when they are not.

[`Packaging/carafe.rb`](Packaging/carafe.rb) is the cask template. It belongs in
a separate `homebrew-carafe` repository, since Homebrew requires taps be named
`homebrew-<tap>`.

---

## Licence

MIT — see [LICENSE](LICENSE).
