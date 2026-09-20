# Reusable dictionary learning API

Status: broader proposed contract. The September 20 backend implementation and measured limits are documented in [original-audio-learning-implementation.md](original-audio-learning-implementation.md). The descriptions below record the September 19 baseline and future design, not the current implementation status. Reviewed against the local FluidVoice long-recording implementation and companion FluidAudio pronunciation-streaming worktree on 2026-09-19. UI entry points and automatic-add policy can be implemented independently after this contract.

## Outcome

A user correction should associate the intended spelling with the actual pronunciation from that dictation. A confirmed, well-aligned original occurrence can supply one real example; the application should not automatically ask for three fresh recordings. Save audio evidence and its derived embedding together, so the spelling, text variants and sound all refer to the same occurrence. These are personalization examples, not acoustic-model weight training.

Manual entry, correction approval, explicit voice enrollment and future automatic additions all call the same learning service. They choose how an addition is initiated; they do not each implement extraction, embedding, persistence or matching rules. No new HTTP server is needed: the internal Swift service is the canonical API, with optional adapters for the existing Local API later.

## What exists today, and review findings

| Path | Current result | Missing for correction-based learning |
|---|---|---|
| Manual dictionary entry | Intended spelling and text triggers | No audio exists unless linked to a spoken occurrence |
| Basic voice training / correction popup training | Text variants collected from new recordings | Popup ignores pronunciationEnrollment; original correction audio is not linked |
| Advanced voice training in dictionary page | Text aliases and model-specific embedding examples | No persisted audio reference; requires three examples |
| Detected correction / Add Only | heardText and correctedText become text replacement | Candidate lacks recording ID, original token span and audio evidence |
| Long-recording matching | Matches existing trained profiles during dictation | Discards encoder features after producing hits; cannot learn an unknown word from those hits alone |

Source anchors: AutomaticDictionaryCorrectionCandidate in AutomaticDictionaryCorrectionTracker.swift; AutomaticDictionaryTrainingSession.persist/addOnlyCorrection; PronunciationEnrollmentCapture and PronunciationDictionaryStore; FluidAudioProvider.pronunciationProfiles/transcribeFinalResult; CustomDictionaryView.finishTrainingSampleStop.

Two runtime gates still require enrollments.count >= 3. Merely saving one embedding would not activate it. They must eventually consume a common eligibility policy, not be changed independently to accept everything.

ASRService retains completed audio only when history and history-audio saving are enabled. That snapshot is consumed by other flows. It is not a reliable learning-evidence API. Also, correction observation starts with inserted text and target PID; inserted text may already contain alias replacements, formatting or AI rewriting. Searching that text for a word is not sufficient to select the correct audio occurrence.

The existing save paths update UserDefaults text entries and a separate JSON pronunciation store. They cannot provide a single atomic learning commit, especially once audio files are added. The shared service must own a recoverable commit boundary before its clients claim success.

## Service boundaries

```swift
// Contract sketch, not compiled production declarations.
protocol DictionaryLearning {
    func prepare(_ request: LearningRequest) async throws -> LearningProposal
    func commit(_ proposal: ProposalID, decision: LearningDecision,
                idempotencyKey: UUID) async throws -> LearningReceipt
    func discard(_ proposal: ProposalID) async
    func retract(_ learningEvent: LearningEventID) async throws
    func snapshot(for model: AcousticModelIdentity) async throws -> DictionaryMatchingSnapshot
}
```

`prepare` resolves evidence, checks eligibility, stages the clip/embedding and produces a reviewable proposal. It must not change active dictionary rules, microphone state, boosting, history settings or UI selection. `commit` activates exactly the prepared content under the current learning policy. A retry with the same idempotency key returns the original receipt. `retract` removes that event's contributions, not an entire word's unrelated examples or aliases.

The service actor coordinates independent components:

- `DictationEvidenceStore`: immutable recording receipts, ephemeral audio ownership and bounded evidence leases.
- `CorrectionAlignmentResolver`: maps the corrected delivered-text span back to the original ASR token occurrence, with explicit ambiguity results.
- `PronunciationEvidenceExtractor`: creates a focal audio example and an embedding using a versioned acoustic backend. No UI or dictionary writes.
- `DictionaryLearningPolicy`: determines confirmation requirements, alias scope and whether an example is eligible for matching.
- `DictionaryLearningRepository`: atomic metadata commits, staged audio files, recovery, migrations and immutable matching snapshots.

FluidAudio owns feature extraction and scoring. FluidVoice owns user intent, text-edit provenance, policy, retention and persistence. A model/search-library swap changes the extractor implementation, not each UI caller.

## Request and evidence identity

`LearningRequest` contains:

- Request/event UUID and optional existing dictionary entry UUID/revision.
- Intended spelling; observed original ASR text when known.
- Source: explicit correction, manual word, fresh voice example or automatic proposal. Source is provenance, not permission to bypass policy.
- Evidence input: a dictation receipt plus delivered-text span, a fresh recording receipt plus focal span, or no audio.
- Confirmation/policy context supplied by the trusted adapter. Reuse must not allow arbitrary callers to assert automatic approval.

A `DictationReceipt` contains a recording UUID, generation, ASR model identity, raw transcript revision, original token timings, delivery ID and the transformation mapping to delivered text. Each edit stage records span mappings where reliable. Rewritten or ambiguous regions are explicitly unmappable. Ranges use named coordinate systems: UTF-16 for text, integer sample offsets for audio, global encoder-frame offsets for features. Never pass a bare range with an assumed unit.

An accepted `PronunciationExample` contains:

- Stable example/event/entry IDs, source recording and original token span.
- Audio asset reference, sample rate/channel format, focal sample range and context range.
- Embedding values/dimension, acoustic model revision, feature-extraction/pooling version and normalization convention.
- Actual heard text and intended spelling, provenance and alignment/quality measurements.
- Policy state and creation time. Quality measurements are not mislabeled probabilities.

Keep distinct examples; do not count retry copies or the same source occurrence as multiple independent recordings. A computed prototype is a cache derived from examples and versioned by entry revision/model identity. Do not persist only its average and throw away its provenance.

## Reusing the actual recording efficiently

1. Capture starts immediately through the existing pipeline. Learning adds no wait before the first PCM.
2. During dictation, existing pronunciation matching continues to reuse each ASR chunk's encoder output. This matching is independent of enrollment.
3. When correction tracking is enabled, finalize a bounded temporary recording receipt without awaiting disk work on the insert path. The receipt covers earlier words too: keeping only the newest 15 seconds cannot learn a correction near the start of a two-minute recording.
4. Retain temporary evidence for the correction-observation window under explicit age, count and byte budgets. A short lease protects an accepted operation from eviction. Budget exhaustion/expiry returns evidenceUnavailable, never waits indefinitely. History recording remains a separate preference and consumer; do not steal its consume-once snapshot.
5. On a confirmed correction, resolve the exact source occurrence and crop its word/phrase with the context needed by the encoder. Prefer compatible retained features when available. Otherwise run one bounded encoder-only pass on the original context window in the background. No second encoder pass is required on every dictation.
6. Persist the accepted focal clip plus necessary bounded context and focal boundaries. The context and extractor identity matter: embedding a tiny isolated crop can differ from embedding that word in its original sentence. Store enough evidence to reproduce the chosen extraction. Do not retain an entire dictation permanently for a single word.
7. Discard temporary recording evidence when the bounded observation/lease ends. Removing an example deletes its audio when no other example references it.

Retention limits must be explicit configuration and tested; the service may not silently remove earlier audio and then attach a same-spelled later occurrence. Sensitive source audio must not appear in logs or ordinary dictionary text exports. Existing audio-history opt-out must not be silently reinterpreted as agreement to permanent full-recording storage; learning retention is an explicit product policy.

## Results and one-example eligibility

Prepare/commit outcomes are explicit, with no permanently pending branches:

| Outcome | Meaning |
|---|---|
| learned | Spelling, accepted sound example and configured text evidence are durably saved and eligible |
| savedTextOnly | Spelling/rule saved; there was no usable audio; never present this as pronunciation learned |
| savedPendingEvidence | Example retained but not eligible yet; include a concrete reason and next action |
| needsConfirmation | Proposed spelling/meaning needs approval before activation |
| needsAudio | Evidence expired, missing or could not be aligned; user may optionally speak once |
| rejected | Unsupported evidence, conflict or invalid request; no active partial writes |
| cancelled | No new active rule; staged artifacts released |

The API accepts one confirmed occurrence. Activation from one example must be justified by evaluation and quality/alignment checks, not by duplicating it three times or replacing the current count gate with a permissive threshold. Strong evidence can activate without three repeats once calibrated; uncertain evidence requests one additional example or remains pending. Existing three-example profiles remain supported during migration.

Text variants and acoustic evidence complement each other. A newly observed alias can be ambiguous common speech, so evidence storage is separate from granting a global unconditional text replacement. Preserve explicitly authored global rules; learned aliases can require acoustic/context support. Never learn from the system's own automatic replacement as if it were a fresh user correction. Homophones require intent/context, not a claim that embeddings can distinguish identical sounds.

## Persistence and event contract

Use a canonical transactional learning repository with versioned entries/examples/alias provenance/learning events. Migrate legacy text entries and pronunciation JSON once with an idempotent version marker; do not leave two independently writable sources of truth. Preserve legacy entry IDs and track missing audio as an explicit legacy state. Use a temporary migration fallback only with a bounded exit and visible failure result.

Stage audio in the same app-support volume, validate content, then atomically rename to its final asset before committing a database reference. A crash before metadata commit leaves an orphan that recovery can remove; an active entry must never point to an uncommitted/missing staged file. Commit the word, examples, alias policy and event receipt together. Startup recovery resolves interrupted transactions and staged/orphan files under a bounded cleanup policy.

Publish a narrow `dictionaryLearningCommitted(revision, changedEntryIDs)` event once after durable success. Its consumers rebuild text-match caches and pronunciation snapshots, coalescing updates. Do not reuse `.parakeetVocabularyDidChange` as the learning event: it has ASR/configuration/UI consumers. Enrolling pronunciation must not implicitly enable boosting, reload unrelated audio hardware or switch the selected model. Trace existing producers/consumers when adapting legacy setters.

Model changes do not compare incompatible vectors. Re-embedding from retained audio is an explicit background migration with a policy/result state; unavailable model/audio keeps the text entry usable without falsely marking acoustic matching ready.

## Implementation sequence

1. Evidence receipt and span-coordinate types; ownership/expiry contract; no automatic additions yet.
2. Extractor API with original context and one-occurrence example storage. Extend ASR/delivery plumbing to retain reliable mappings; keep insertion fast.
3. Transactional learning service and policy results; migrate legacy profile/alias adapters. Replace duplicated three-count gates with the common eligibility result only after one-example evaluation.
4. Route user-approved correction through the API; use the original audio when mapped, with truthful fallback when unavailable.
5. Route fresh voice/manual entry through the same service. Fresh voice becomes an optional source of extra evidence; manual text without a recording cannot manufacture a pronunciation example.
6. Add automatic proposal/approval rules as another adapter after precision validation. Its trigger and UI can evolve without changing extraction/storage contracts.

## Review and verification gates

Long-recording review: source confirms stable matches are retained once, tail candidates replace earlier tail candidates, global offsets reach final token reconciliation, old recording generations cannot publish, and cancelled current preview state is cleared without resetting newer state. Existing evidence is in `scratch/pronunciation-streaming-benchmark/RESULTS.md`: boundary parity, repeated-word/overlap checks, two-minute provider regression and multilingual batch parity. This review does not prove false-positive safety for every accent; previous 34 ms is remaining library processing, not end-to-end insertion latency.

Before enabling correction-based learning, test:

- Same evidence through different UI/API callers produces the same entry/example; retry produces no duplicate example.
- A correction at the first minute and the same word at the second minute binds to the selected occurrence only.
- Formatting, AI rewriting and multiword-to-one-word corrections preserve a known mapping or reject acoustic learning; never guess.
- Missing/expired audio yields a truthful text-only or needsAudio result.
- Saving without audio never reports learned; saving one genuine example never counts it as three.
- Persist failure/crash/restart, stale proposal revision, cancel, delete during preparation and retraction leave no partial active entry or lost unrelated examples.
- Model mismatch, duplicate events, incompatible embeddings and rejected proposals cannot become active matches.
- Both approved correction and future automatic adapters pass the same conformance suite; neither changes boosting, microphone lifecycle, history preferences, live text or other entries as a side effect.
- Original recorded speech is tested against target-present, target-absent/confusable and already-correct speech across accents. Report recall AND false substitutions before selecting activation thresholds.
- Measure correction preparation separately from dictation stop latency, and repeat long-recording tests after adding evidence retention. Test bounded memory/disk, expiry and cleanup during rapid new recordings.

No automatic-learning behavior or audio-retention change was implemented as part of this design review.
