# Original-audio correction learning

Implementation work, September 20, 2026. The existing correction UI now schedules original-audio learning after an approved Add Only or trained-replacement save. The broader API proposal in `dictionary-learning-api.md` remains a future contract, not a claim that every proposed migration or UI adapter is implemented.

## Implemented path

1. Parakeet returns original word timings separately from rewritten output. Normal dictation retains an immutable PCM receipt only when correction learning is enabled. History audio ownership is independent. Boosted output cannot supply trustworthy provenance and falls back to text-only learning.
2. External delivery gives the correction tracker that exact receipt. The selected UTF-16 edit maps to its original occurrence; unchanged lexical content maps by ordinal, while edited text requires unique surrounding anchors. Ambiguous rewrites, invalid timing and expired evidence are rejected.
3. The tracker crops up to 14.88 seconds of original context on a utility task before presenting the existing popup. It never searches for a same-spelled occurrence elsewhere after alignment fails.
4. The existing approval saves the text rule immediately. `DictionaryAudioLearningService.learn(entry:evidenceID:evidence:)` schedules optional encoder-only extraction, reusing the loaded matching Parakeet encoder when available and loading the recorded model only as a fallback. This API accepts immutable evidence, not UI views or microphone controls.
5. The bounded worker cancels when an exclusive audio activity starts and retries after it ends. Four pending clips, a 120-second deadline and one active extraction bound memory and work. Unsupported, expired, failed or over-budget work leaves the approved text correction intact. Logs never contain dictated text or audio.
6. `PronunciationDictionaryStore.learnOriginalAudio` writes local PCM metadata before atomically activating its embedding in the profile index. It links entry/event/recording IDs, original occurrence, observed text, model and extractor version. Repeated event IDs and repeated source occurrences do not count as additional examples. A retry reports whether it inserted anything, so cancellation cannot retract an older successful event.
7. Entry snapshots and store revisions reject stale completion. Deletion removes associated audio. Retraction removes only the corresponding example. Valid-index startup cleanup removes aged unreferenced audio left by interrupted writes. Raw clips are excluded from ordinary dictionary exports; profile backups preserve embeddings and provenance, not clip files.
8. One original approved occurrence is eligible through the same policy used by both short and incremental dictation. Existing manual enrollment still requires three examples. No sample is copied to satisfy that count.

The temporary receipt accepts recordings up to 15 minutes and expires after 120 seconds. This is a memory bound, not the model's 15-second input limit. Longer recordings currently retain text-only correction learning. Stored context clips are Float32 little-endian, 16 kHz mono. At most ten examples per profile are retained; there is no global disk quota yet.

## Combining evidence

Known observed variants retain their approved text fallback. Acoustic matches for original-audio profiles require cosine score 0.70 when the recognized phrase matches a known variant, or 0.85 for a new variant. These are conservative experimental thresholds, not probabilities or universally calibrated guarantees. A near tie between different intended labels within 0.05 is rejected. The two strongest labels per word are indexed so conflict checks do not compare every candidate with every other candidate. Changed intended meanings cannot reuse original-audio evidence by merely retaining the entry UUID.

An initial experiment required acoustic confirmation before applying a learned text alias. Real-speech tests showed a substantial recall regression, so that design was removed. A weak acoustic score does not establish that a familiar text correction is wrong. The current combination allows either mechanism to recover a miss by the other. Global text-alias ambiguity is not solved by this change.

## Evidence and limits

- 62 affected app tests passed together, including the real two-minute streaming regression, real-audio save/reuse, repeated-occurrence alignment, cancellation/retry, expiry, invalid evidence, deletion, imports and conflicting matches. All eleven learning tests passed again after review, followed by focused retry/encoder-reuse and stale-meaning checks.
- Encoder-only extraction reproduces the normal encoder's embedding exactly on the same real audio context and releases prepared handles after success/cancellation. Two XCTest cases plus eleven matcher/index tests passed.
- Controlled ASR-error injection verifies that text recovers an acoustic miss, audio recovers an unseen text variant, and unrelated speech stays unchanged. This is wiring regression evidence, not a speech-accuracy benchmark.
- Real FLEURS evaluation: 27 available clips, eight languages, 536 timed words. Eleven repeated targets produced 26 cross-clip trials; five longer clips were excluded. Reference-to-ASR word alignment supplies evaluation labels. Full search, using a separate context re-encode for enrollment, scored text-only 19 true/2 false substitutions, acoustic-only at 0.70 scored 3 true/1 false, and the current combination scored 19 true/2 false. There were 21 target and 547 non-target word opportunities. The combined method preserved text recall but did not beat it on this small set.
- Most repeated targets in that set are common words, not personalized names. Speakers were not constrained to match enrollment. It cannot establish same-user accent robustness or general custom-name accuracy. More realistic held-out corrections are still required before claiming superiority or tuning the novel-variant threshold.
- Isolated reconciliation on a ten-minute/1,200-token fixture averaged 1.42 ms for one profile, 1.46 ms for ten, and 6.50 ms for 1,000. It measures cached matches to text, not ASR/search or whole Stop latency. The real original-audio background round trip took about 120 ms, including model loading/persistence and up to 10 ms polling granularity; it is outside the delivery path. Reusing the already-loaded encoder measured 40.7 ms for the same ten-second context, returned identical vectors, and preserved the next transcription.
- Earlier paired ten-minute streaming benchmark remains 46.109 ms off versus 62.467 ms on with 1,000 profiles, a 16.358 ms mean difference. The new end-to-end live-microphone overhead has not been remeasured. See `scratch/pronunciation-stage-profile/ON_OFF_STOP_OVERHEAD.md`.

Evaluation scripts and raw outputs: `scratch/original-audio-learning/evaluation/`. They are local research artifacts, not production app assets. There is no guarantee of perfect accuracy, no new UI, no model-weight training, no enabling of vocabulary boosting, and no migration of every legacy voice-training adapter in this patch.

Validation status: scoped service lint is clean. Full-source format and strict lint ran; restoring unrelated formatting left 623 pre-existing lint findings, with none on the changed tracked code lines. The signed private FI build is the local packaging check; it is not a production bridge/release gate.

## Composition regression follow-up

A verified failure showed that `fluid -> Fluid Voice` expanded an already-correct acoustic output into `Fluid Voice Voice`. The text matcher now protects completed occurrences of a rule's own output when that output contains a partial trigger. Ordinary rules retain the existing fast path. Tests cover independent uncorrected occurrences, capitalization, word boundaries, literal replacement text, and a combined sentence where text-only and acoustic-only each miss a different occurrence. This is deterministic composition proof, not a new field-accuracy claim. All 65 affected app tests passed, and the signed private FI build succeeded.


## Approved-path and same-speaker follow-up

The production correction detector, original-occurrence resolver, existing Add Only session, background encoder and isolated durable store now run together in a real-audio integration test. Detection alone creates no pronunciation profile; approval saves the text rule and then exactly one linked enrollment. Dependency injection leaves the existing UI call unchanged. All 67 affected app tests passed together with no failures or skipped tests.

A separate real 60-second speech experiment enrolled the first occurrence and excluded its entire 14.88-second window from subsequent searches. Later NVIDIA and AI occurrences scored 0.877 and 0.914. A later Jensen occurrence scored 0.779, showing that the 0.85 novel-variant threshold can still miss useful matches; the known text fallback remains necessary. A broad, poorly aligned NVIDIA span scored 0.754 and correctly failed the novel-variant threshold. These labels are ASR-derived, not independent human ground truth, so this is diagnostic evidence rather than word-error-rate proof.

The experiment also found a concrete false edit: Jensen's scored 0.884 against Jensen and could lose its possessive. Original-audio matching now preserves straight or curly apostrophe possessives unless an approved observed variant explicitly taught their removal. Existing possessive labels are not doubled. This is a narrow English possessive safeguard, not a general inflection model. Tests cover both preservation and explicit removal.

Raw experiment: scratch/original-audio-learning/evaluation/personal-trials.json and Sources/PersonalProof/main.swift. No thresholds were relaxed from this small sample.


## Automatic activation follow-up

The final consumer audit found that saved original-audio profiles were still gated by Advanced Preview. Approved original-audio profiles now participate automatically while automatic dictionary learning is enabled, even with Advanced Preview off. Manual-only acoustic profiles remain behind Advanced Preview. Pinned offline options and meeting policy do not inherit automatic matching.

The provider takes a bounded profile snapshot from the store actor on the first transcription call of a recording, after microphone capture has started. Recording reset invalidates that snapshot so a newly approved word is available next time. Empty or ineligible profiles do not switch dictation to the pronunciation path. Short, word-timing and long incremental paths share profile selection; original evidence with a changed intended label is rejected before search, rather than relabelled.

The real-audio approval regression now starts with an empty profile snapshot, approves and learns the correction, resets for the next recording, and verifies actual replacement in short, word-timed and 60-second incremental dictation with Advanced Preview off. It also checks that disabling automatic learning and Advanced Preview restores baseline ASR. This repeated-recording proof is functional validation, not held-out recognition accuracy.

Validation: 76 dictionary/pronunciation and meeting-policy tests passed together, plus the separate production meeting-provider isolation test. Scoped provider lint is clean; full-source formatting and strict lint ran with existing repository violations preserved. The signed private FI build succeeded. Debug pronunciation timings are not treated as optimized latency measurements.
