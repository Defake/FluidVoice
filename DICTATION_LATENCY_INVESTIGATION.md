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
