# Clipboard backup regression tests

Run with a full Xcode toolchain (without changing the system-wide selection):

```sh
DEVELOPER_DIR=/Applications/Xcode-beta6.app/Contents/Developer sh Tests/run_clipboard_backup_reproduction.sh
DEVELOPER_DIR=/Applications/Xcode-beta6.app/Contents/Developer sh scripts/test_dictation_target.sh
```

The backup runner compiles production `PasteDeliveryCoordinator.swift`, including
`SystemPasteboardManager`, and `DictationTargetPolicy.swift`. Each case uses an isolated
named macOS pasteboard. Injected command posters send no keys; optional I/O failures
are injected at the pasteboard boundary. Logging and unused keyboard constants are
standalone adapters. The general clipboard, preferences, microphone, and installed app
are not accessed by this runner.

31 cases cover:

- Backup off/on with successful posting, failed snapshots, failed writes before and
  after touching the clipboard, failed command posting, and newer user copies during
  failed writes/posts or before settlement.
- Both experimental-toggle positions, with external focus present or missing, using
  the production preparation boundary and an injected unsuccessful focus restoration.
- A backup queued behind an active paste, with backup off/on and newer user copies.
- Stale failed preparation after a newer user copy, paste delivery, or standalone copy.

Checks include delivery results, final clipboard text, permanent-copy call counts,
absence of duplicate backup writes, zero commands after failed preparation, and no
clipboard mutation for disabled backup when insertion is skipped. Successful posting
is a simulated command-post result, not proof that a destination app consumed text.

Before the fix, the first 10 cases had three failures: with backup enabled,
snapshot/write/command failure retained the old clipboard instead of the transcript.
The runner now expects all cases to pass and exits nonzero on a regression. The
existing XCTest assertion for command failure with backup enabled is also updated.

The separate destination-policy suite covers 10 app/field-switch and missing-target
cases. These tests do not perform live Accessibility restoration, record speech, or
exercise ContentView/history persistence end to end. Failed preparation is injected
into the same production coordinator boundary used by ContentView.
