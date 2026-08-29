# Carafe

A macOS app that reminds you to drink water through the day.

Carafe lives in your menu bar showing how much water you have left to drink
today. Log a glass and the water level drops.

---

## Install

Download the latest `.zip` from
[Releases](https://github.com/Tristan-deAlwis/Carafe/releases), unzip it, and
drag `Carafe.app` to `/Applications`.

Requires macOS 14 (Sonoma) or later. Works on Apple silicon and Intel.

### If macOS says Carafe is "damaged"

It isn't — that's the message macOS shows for apps not yet notarized by Apple. To
open it anyway:

```sh
xattr -d com.apple.quarantine /Applications/Carafe.app
```

---

## Using it

| | |
|---|---|
| **Log a glass** | Click the menu bar icon, then **Log** |
| **A different amount** | The **⋯** menu beside it |
| **Undo** | The **−** button |
| **Fix a past day** | Click any bar in the history strip |
| **Settings** | The gear in the top corner |

You can set your daily goal, glass size, units (ml or fl oz), how often to be
reminded, the hours you want reminders, and whether Carafe starts at login.

Under the carafe is your last seven days, with a streak count. A day counts
toward your streak when you hit its goal, and today never breaks it while it's
still in progress.

### Fixing a past day

Forgot to log something yesterday? Click any bar in the history strip and set
what you actually drank. Days you never recorded can be filled in the same way.

Each day remembers the goal it was set at the time, so raising your goal won't
break an old streak.

### Reminders

macOS only shows notifications from apps signed with an Apple developer
certificate. Carafe doesn't have one yet, so instead of a notification it marks
its menu bar icon and plays a soft sound when it's time to drink. Opening Carafe
clears it.

---

## Your data

Carafe keeps your history in a plain JSON file you can read and back up yourself:

```
~/Library/Application Support/Carafe/history.json
```

Under **Settings › Your data**:

| | |
|---|---|
| **Export → Backup (JSON)** | Your history and settings in one file |
| **Export → Spreadsheet (CSV)** | Daily totals for Excel or Numbers |
| **Restore…** | Load a backup. Replaces what's there, and asks first |
| **Show Files** | Open the folder in Finder |

---

## Licence

MIT — see [LICENSE](LICENSE).
