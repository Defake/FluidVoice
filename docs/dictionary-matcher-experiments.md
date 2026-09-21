# Dictionary matcher experiments

All options live under **Settings → Experimental → Dictionary matching experiments**, are searchable, and default to off. This is an optional test implementation, not a production accuracy claim.

## Correction flow

1. Parakeet accepts an acoustic match and actually replaces a spoken word with a dictionary label.
2. The provider attaches the accepted occurrence's entry ID, source word range, model/profile identity, and normalized audio features to that dictation's short-lived learning context.
3. After external text delivery, the existing correction observer sees the user edit the inserted label.
4. Only a unique, complete label in unchanged delivered text can be linked. No mapping means no negative example. Repeated labels, expired contexts, AI rewrites, partial edits, case-only edits and punctuation-only edits are ignored. Ordinary edits to a dictionary entry are not evidence of a spoken false positive.
5. The correction overlay asks **Was this a wrong match?** Choose **That Was a Wrong Match** only when a different word was spoken. A spelling/style edit is not automatically a false positive.
6. Confirmation stores only that occurrence's audio features. It does not add a text replacement, modify a positive enrollment, or enroll the corrected text as a new word.
7. With negative comparison enabled, future matching can veto a close match to the confirmed mistake. A single negative does not necessarily generalize to other mistakes.

Collection works with the positive whole-pronunciation experiment or the existing legacy edge matcher, and only for occurrences that reach the acoustic replacement path. It does not watch arbitrary edits or retroactively mine history. The existing correction observer requires Accessibility support in the receiving app. Internal dictionary playground edits are not automatically connected to this external correction observer.

## Independent switches

| Switch | Behavior |
|---|---|
| Compare the whole pronunciation | Original three positive training recordings; normalized frames, ordered alignment, calibrated mean and lower-quartile checks. Missing reference audio falls back to existing matching. |
| Learn from confirmed wrong matches | Offers the wrong-match confirmation after an attributable correction. Does not itself change acceptance decisions. |
| Use saved wrong-match examples | Optional veto after an otherwise accepted candidate. No examples is a no-op. It never creates a new acceptance. |
| Clear wrong-match examples | Deletes the separate example store and invalidates older pending saves. Leaves dictionary entries and positive recordings untouched. |

Turning all three switches off restores the pre-existing matcher configuration. The existing independent `DictionaryEdgeMatchingEnabled` preference is preserved. No preferences are enabled by this implementation.

With experiments enabled, new voice enrollments retain their original training audio locally so the positive frames can be rebuilt. Existing words without that audio keep their prior matcher until re-recorded. Negative correction learning itself persists features only, not PCM or corrected text. When automatic positive learning is off, the correction observer does not retain the full dictation PCM for negative learning.

## Algorithm and compatibility

- Positive matcher: existing Parakeet encoder, exact-length inputs, RMS .05/peak .95 normalization with gain cap 32. Reference-frame-weighted DTW, .25 time band and .05 stretch penalty. Best-reference calibrated mean ≥ .70 and lower quartile ≥ .55. These are research-selected values, with known noise/timing limitations.
- Negative veto: symmetric temporal similarity to the saved mistake ≥ .75 and greater than the best positive by > .05. This is deliberately conservative for one-example learning; it is not the earlier larger, labeled-example-bank research result.
- Reference identity includes model, extractor version, label, enrollment audio identities and vectors. Renaming, retraining or changing models makes old negatives ineligible.
- At most 6 negative examples per word and 32 total; file size ≤ 32 MB. Duplicate confirmation IDs are ignored. Corrupt optional banks produce no veto; saving reports failure rather than silently overwriting corrupt data.
- Confirmation checks the entry/profile before and after the store write. Cancellation, disabling collection, changed profiles, expiry, and clearing invalidate stale work.
- Separate store: `~/Library/Application Support/FluidVoice/dictionary-negative-examples-v1.plist`.
- Existing loaded Core ML models are reused. No dependency edits, new model downloads, decoder pass, or opening-audio delays. Frame extraction and comparison run off the main actor. Reference caches are bounded to 8 profiles; candidate cuts retain the existing 3-per-word/24-total bound.
- Candidate discovery and ambiguity handling remain in the existing pipeline. Temporal acceptance is passed separately from the original score, preserving ranking rather than replacing every score with a constant.
- Only supported Parakeet/Apple Silicon paths run the encoder. Other providers and missing evidence retain existing behavior. Cross-speaker accuracy and older-device runtime have not been established.

## Replace or remove

The independent decision layer is `DictionaryExperimentalMatcher.swift`. The encoder adapter is `DictionaryTemporalEncoder.swift`. Negative provenance/resolution/storage is isolated in `DictionaryNegativeExamples.swift`; settings are in `DictionaryMatcherExperimentSettings.swift`.

Integration points are the final and incremental refinement paths in `FluidAudioProvider`, learning context transport in `DictionaryLearningEvidence`/`ASRService`, and the existing correction tracker/session/overlay. `DictionaryPronunciationExperiment.enabled` enables the edge discovery path only for the positive comparator, not for collection alone. Remove these hooks and the four modules to remove the feature; no positive-store migration is required. The optional negative file can be cleared independently.

## Validation and manual test

Run `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer sh Tests/run_dictionary_matcher_experiment_tests.sh`. An optional research-artifact directory argument additionally compares all 392 retained research cut decisions against the production scorer. Tests use only temporary storage and do not change real preferences or recordings.

Build with `INSTALL_APP=0 LAUNCH_APP=0 sh build_with_FI_incremental.sh` (appropriate installed Xcode selected, development signing preserved). This work has not installed or launched a replacement app.

Manual test after installing a test build:

1. Enable whole-pronunciation matching and wrong-match learning. Use a word with three saved training recordings. Keep negative comparison off to collect without changing rejection.
2. Dictate into an external editor with Accessibility support. Correct an actual dictionary replacement to another word and leave the edited word. Confirm **That Was a Wrong Match** in the overlay.
3. Enable negative comparison and try the same mistake plus genuine pronunciations of the dictionary word. Check both rejected mistakes and unintended missed correct words.
4. Toggle comparison off to compare behavior; clear the examples to reset. Rename/retrain a word and verify old negatives no longer affect it.
5. Check the overlay at narrow widths and Settings in light/dark appearances. These visible flows and live Accessibility delivery have not been manually verified in this change.

Verified for this change: private FI Release build passed with install/launch disabled; 816 isolated component/parity checks passed; production scorer matched all 392 archived cut decisions; production encoder frames matched all six original enrollment extractions exactly; strict lint passed for the four new implementation files. Nineteen unrelated tracked WIP patches were unchanged. Full app XCTest, installed UI, live correction observation and older-Mac testing were not run. Existing replay diagnostics remain the original matcher and now show that limitation when experiments are enabled.
