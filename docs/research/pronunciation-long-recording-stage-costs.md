# Long-recording finalization stage review — 2026-09-19

Measured the actual 120-second all-after-stop path with one pronunciation prototype, Parakeet v3, no vocabulary boosting, on Apple M5 Max / 128 GiB. Fixture: public jensen-60s.wav repeated twice, 1,920,000 samples at 16 kHz, 1,571 transcript characters. Nine stable windows plus one tail window. Two warmup runs, seven measured Release runs. Instrumentation is in a scratch copy of the exact companion library source; production sources were not instrumented. All profiled runs produced identical text.

| Stage | Median milliseconds |
|---|---:|
| preprocessor | 12.48 |
| encoder | 245.48 |
| decode | 277.84 |
| pronunciation | 8.20 |
| mergeAndText | 0.32 |
| other | 0.78 |
| Full finalization | 545.73 |

Pronunciation includes 1.26 ms copying existing encoder features across all ten windows; that is nested, not an extra additive stage. The remainder builds/scans pronunciation candidates. Encoder and decoder together account for roughly 96% of this workload. No second acoustic encoder is run for matching. Stage medians are separately aggregated, so their sum can differ slightly from the median total.

Preprocessor includes mel/input preparation; encoder includes acoustic feature inference and its prepared-buffer management. Decode includes token prediction, extraction and associated buffer release. Merge/text covers overlap merging and final result construction. Other is per-run residual bookkeeping, PCM append/copy/chunk preparation and actor-call overhead. Model initialization is outside the measurement.

The earlier 546 ms to 34 ms result compares all work after stop with reusing stable windows already processed during dictation. It is not a 16x reduction in total compute, and it is not microphone-to-keystroke latency. Raw app delivery, dictionary text regexes and AI cleanup are outside this library benchmark. The prior 100-prototype workload used duplicate durations/vectors; diverse dictionary durations can cost more.

Evidence: scratch/pronunciation-stage-profile/results.json and results.log; scratch/pronunciation-stage-profile/Sources/Profile/main.swift; instrumented library under FluidAudioProfiled. The unchanged baseline and lifecycle/accuracy limitations are documented in scratch/pronunciation-streaming-benchmark/RESULTS.md.

Review checks already run on the implementation: two-minute app parity and stale-recording regression, repeated-word/overlap unit checks, 14 library unit tests, eight-language/three-pattern batch parity, Release boundary/cancellation assertions, signed FI install. Scoped lint has zero violations. Required whole-repo format/lint was run: unrelated formatter edits were restored; full lint reports 623 existing violations outside these two source files. No unrelated Feedback edits are included in the dictionary commits.

Companion FluidAudio commit: 97ed23265098a78a09378659063d52dee908f9e0. The app commit pins that revision; the local working tree retains a development override. The library commit must be published before a fresh machine can resolve the app pin. No pushes performed.
