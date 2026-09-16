# Dictation start/stop latency investigation

Branch: `B/overlay-smoked-glass`. Host: Apple silicon, macOS 27 beta.
Goal: instant start, instant stop, overlay gone by the time text is pasted.
Rule: no behavior changes in audio capture (`DirectCoreAudioInput`, capture
path in `ASRService`). Any finding there is logged, not fixed here.

## Method

- Scripted trigger: `FluidDebugRemoteToggleEnabled` defaults flag plus the
  `com.FluidApp.debug.toggleRecording` distributed notification runs the
  exact Right Option hotkey path. Driver CLI lives in the session scratchpad
  (`fluidctl`, `fluid_toggle.sh`).
- Timing: `rg 'HIDE_NOW|STOP_TRACE|CLOSE_DETAIL|DICTATION_SUMMARY' ~/Library/Logs/Fluid/Fluid.log`
- Main-thread stacks: `sample FluidVoice 2 1` started 300 ms before the
  scripted stop or start, so the aggregate is the stall itself.

## Findings and fixes (chronological)

### 1. Overlay hide blocked on WindowServer fences (fixed, 094b8d0e)

Every window-management call (`orderOut`, `setFrameOrigin` offscreen park,
the `_windowMoved` echo, `orderFrontRegardless`, `ignoresMouseEvents`,
explicit `CATransaction.flush`) goes through `NSWMWindowCoordinator
performTransactionUsingBlock` -> `CAFenceHandle newFenceFromDefaultServer`
-> `mach_msg` and blocks until WindowServer answers. Measured 70-300 ms each.
Hide now sets `alphaValue = 0` only. Hide time: 216 ms -> 37 us.

| Build | Hide call | Lock held (typical) |
| --- | ---: | ---: |
| before | 82-216 ms | 300-660 ms |
| after | 28-37 us | 150-250 ms |


### 2. Final ASR ran on the main thread (fixed, 761f2c8c)

`final_executor_begin mainThread=true`: the TranscriptionExecutor closure
inherited main-actor isolation from the @MainActor method that formed it.
Inference (40-130 ms) blocked the run loop and every await hop waited for a
busy main thread. Detached with `Task.detached`. Lock 249 ms -> 64 ms on a
2 s silent recording. Audio capture untouched.

### 3. Hide transaction committed 550-660 ms late (fixed, ebcc71ab)

New metric `HIDE_COMMIT` = hide call -> transaction carrying alpha 0 committed
to WindowServer. This is the "box stays after the paste" number. SwiftUI state
clears, the `ignoresMouseEvents` fence (80-100 ms) and the status item refresh
were queued into the same run loop turn as the alpha change. All moved into a
`CATransaction.setCompletionBlock`. HIDE_COMMIT 551-658 ms -> 15-18 ms.

### 4. Status icon redrawn on every start and stop (fixed, fea6d6c9)

`updateMenuBarIcon` assigned a fresh `NSImage` on each `isRunning` change even
though the template icon never changes. Each assignment: status item redraw,
`NSStatusItemScene updateSettings`, `BKSAnimationFenceHandle` fence, ~118 ms in
samples, plus a `CABackingStoreSynchronize` wait. Assign once.

### 5. Transcribing status fired for most utterances (fixed, 526c2aa2)

Delay raised 100 ms -> 250 ms. Below that the status only added an overlay
re-render that delayed the result it announced.

### 6. Overlay re-evaluated ~94 times a second while recording (fixed, 6335acc4)

Root of the sluggish feel. Audio levels hit `NotchContentState` (an
ObservableObject observed by the whole overlay) once per audio buffer. 1 s
sample during silent recording: 312 ms of SwiftUI graph updates on main.
Level moved to `OverlayAudioLevelState`, observed only by the waveform,
throttled to 30 Hz. Graph updates during recording: ~20 ms/s.

### Warm stop after fixes 1-6 (2 s silent recording)

| Metric | Before | After |
| --- | ---: | ---: |
| Shortcut lock held | 250-660 ms | 54-77 ms |
| Inference -> caller wait | 90-190 ms | 0 ms |
| HIDE_COMMIT | 550-660 ms | 14-17 ms |
| SHOW_COMMIT (start -> first frame committed) | n/a | 10-27 ms |

### 7. Every CA commit blocks the main thread under WindowServer load (root, external)

2 ms samples during silent recording: 50-95% of main-thread samples sit in
`CA::Render::Message::send_message`, i.e. waiting for WindowServer to accept a
commit. WindowServer runs at 42-60% CPU on this host with FluidVoice quit
(macOS 27 beta, other apps). Any overlay frame committed while a stop is in
flight delays the result hop back to the main actor by 90-190 ms, and the
alpha 0 commit itself can wait 200-700 ms.

A/B results (3 runs each, HIDE_COMMIT / mid-recording caSend fraction):

| Variant | Effect |
| --- | --- |
| Material velvet / original / smokedGlass | no difference; blocking is per commit, not per material |
| Waveform 30 Hz -> 10 Hz | fewer commits, but a single commit still blocks 80% of a second when the server is busy |
| Transcription sounds off | no improvement (HIDE_COMMIT ~200 ms consistently) |
| Explicit `CATransaction.flush()` after alpha 0 | regression: the flush itself blocked 300-550 ms. Reverted. |
| Freeze waveform at stop begin (fcb54e49) | removes our own in-flight frames from the stop window |

Warm stop with a quiet WindowServer: lock 54-77 ms, HIDE_COMMIT 13-18 ms,
SHOW_COMMIT 8-17 ms, rapid restart accepted 120 ms after unlock. With a
saturated WindowServer the same code shows HIDE_COMMIT 200-700 ms; nothing in
our process is running then, the commit is queued at the server.

### 8. Rapid restart (stop, start 150 ms later)

Accepted every time after the fixes (no `shortcutRejected`). Show cost on a
rapid restart was 136-250 ms (orderFront fence 40 ms + first-frame flush
95 ms) versus 9-12 ms cold; the deferred mouse-events fence and the guarded
state publishes reduce it, the remaining cost is the first-frame commit.

## Status for the morning

Committed on `B/overlay-smoked-glass` (all builds installed to /Applications):

1. a1b9adfa feat(overlay): closing animation opt-in setting
2. 974cad2b chore(diagnostics): stop path traces
3. 094b8d0e perf(overlay): hide by alpha, no window transactions
4. 238ff3f4 chore(hotkey): local debug toggle trigger
5. 761f2c8c perf(asr): final transcription off the main actor
6. ebcc71ab perf(overlay): commit hide before post-stop state work
7. fea6d6c9 perf(menubar): stop redrawing the identical status icon
8. 526c2aa2 perf(asr): Transcribing status delay 250 ms
9. 6335acc4 perf(overlay): waveform level isolated and throttled
10. 22270dcc perf(asr): cancel Transcribing status right after inference
11. fcb54e49 perf(overlay): freeze waveform at stop, defer mouse fence

Not done / open:

- Real speech through the mic was not exercised by script (text-to-speech
  through the speakers did not reach the input device). The text delivery
  path (typing, history append, overlay observing TranscriptionHistoryStore)
  was measured only on the older builds: typing 1.4-2 ms.
- The overlay still observes SettingsStore, AppServices, ActiveAppMonitor and
  TranscriptionHistoryStore as whole objects; any publish on those
  re-evaluates the whole body (~3-4 ms) and commits a frame.
- `FluidDebugRemoteToggleEnabled` is set in defaults on this machine so the
  scripted trigger works. Remove with
  `defaults delete com.FluidApp.app FluidDebugRemoteToggleEnabled`.
- Diagnostics builds used `LOCAL_SIGNING_XCCONFIG` pointing at a scratch
  xcconfig adding `FLUIDVOICE_DIAGNOSTICS`; the final installed build is a
  plain Release build without it.

### 9. No-text-field detection (51e62364)

`DeliveryTargetAssessment.assessFocusedElement()` runs inside
`TypingService.typeTextInstantly`, so every delivery path and the retry
button go through it. Rule, in order:

1. Accessibility not trusted, focused element unreadable, role unreadable ->
   unknown, paste as before.
2. Role in {AXTextField, AXTextArea, AXComboBox, AXSecureTextField} or
   AXValue settable -> editable, paste.
3. Role in the never-text set (buttons, menus, static text, images, links,
   sliders, toolbars, windows, sheets, application) -> notEditable: transcript
   stays on the clipboard, overlay shows "Not in a text field" with Copy.
4. Any other role (AXGroup, AXWebArea, AXList, AXTable, AXCell, AXScrollArea...)
   -> unknown, paste as before. Table roles are deliberately here: a selected
   spreadsheet cell accepts pasted text. No per-app rules.

Verified via the `FOCUS_ASSESS at=stop` log line (0.3-1.2 ms per stop):
Finder desktop -> unknown (AXList), Stickies and TextEdit -> editable
(AXTextArea), FluidVoice's own window -> unknown (AXScrollArea). The refuse
branch was not exercised with real speech; a button or menu focus at stop
would trigger it.
### 10. Paste read-back verification

`PasteVerifier` (TypingService, off-main after the paste command):

- Snapshot before: focused element, role, AXValue (skipped above 60k chars),
  AXNumberOfCharacters, AXSelectedTextRange.
- Read back at 150 ms and again at 500 ms. Same element required.
- confirmed when the text appears in the value, or the character count or
  caret advanced by the text length.
- notLanded only when value, count and caret were all readable and all
  unchanged on both reads. Then the overlay comes back with "Text was not
  inserted" and Copy.
- everything else unknown and silent (Finder, most containers, apps that
  expose no value).

Verified with the paste-last debug trigger: Stickies -> confirmed by value in
165 ms; Finder desktop -> unknown (nothing readable); Claude Desktop with a
button focused -> refused before pasting by rule 9. The Claude Desktop
"nothing focused" case reports AXGroup and needs a real dictation to see what
the read-back returns; check `rg PASTE_VERIFY ~/Library/Logs/Fluid/Fluid.log`.

## Measurement caveats

- `OverlayCloseRunLoopProbe` (`CLOSE_DETAIL runLoop occupiedMs`) over-reports on
  macOS 27: the loop runs in non-common modes during the AppKit update cycle,
  so idle waits get counted as occupied. Use HIDE_COMMIT, SHOW_COMMIT,
  heldMs and the ASR_BENCH executor lines instead.
- `sample` at 1 ms perturbs the app (adds ~1 s stalls). Use 5 ms or 2 ms
  for at most 1 s windows.
- First cycle after launch is slower (SHOW_COMMIT ~170 ms, HIDE_COMMIT
  ~300 ms). Warm-up, not regression.
- WindowServer sits at ~28% CPU idle on this host. Every commit that
  redraws a bitmap-backed layer waits 50-100 ms in `wait_for_synchronize`.
  The fixes above remove our commits from the critical path; they cannot
  make WindowServer faster.

## Not touched

- Audio capture start: `START()` -> first PCM is 90-235 ms. Mic path, out
  of scope by rule. Logged as `Audio capture running after first PCM`.
- `ignoresMouseEvents = true` after each hide still costs a 70-90 ms fence
  on the main thread (post-commit, so not visible). It exists because an
  alpha 0 panel could otherwise swallow clicks.
- The closing-animation setting path (`hide()` with animation on) still
  parks the window offscreen.
