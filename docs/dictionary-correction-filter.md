# Automatic correction identification

Automatic learning now requires one word on each side of the edit. Manual dictionary entry and existing replacements are unchanged.

The observer still collects edits and waits for a pause. `AutomaticDictionaryCorrectionDetector` expands the accumulated edit to token boundaries; `DictionaryCorrectionEditPolicy` checks eligibility before suggestion frequency counting, audio preparation, or either learning prompt. The negative evidence resolver also checks this policy directly before validating the original accepted match.

## Policy

- Reject whitespace-separated phrases and punctuation-separated text such as `bar,baz` or `bar/baz`.
- Keep internal apostrophes and hyphens for names.
- Reject symmetric English inflection patterns: `s`, sibilant `es`, consonant `y` to `ies`, possessive `'s`, and regular `ed`/`ing` for stems of at least four letters, including final-e removal.
- Preserve insertion-only spelling repairs, substantially different single words, accents, other scripts, and deliberate capitalization. Existing negative learning still rejects case-only changes.
- No dictionary lookup, model inference, network work, new observation, or persisted settings.

## Limits and false negatives

Text alone cannot distinguish a plural from every name repair: `Luca` to `Lucas` looks like a plural and is suppressed. Short stems are exempt to retain repairs such as `Jo` to `Jos`. This is not complete morphology: irregular changes, doubled consonants, and other languages are not inferred. No general edit-distance threshold is used because recognition can produce very different spellings of names. Manual entry remains available for filtered corrections.

The word boundary is lexical, not language-specific segmentation: unspaced scripts are preserved. Compound names with hyphens are allowed. A user pausing mid-edit can still produce an ambiguous single-word candidate; explicit confirmation remains necessary.

## Verification and replacement

`Tests/run_dictionary_correction_tests.sh` compiles the production detector and policy against isolated surrounding data types. It checks rejection and retention examples, observer endpoint eligibility, accumulated typing, undo, punctuation, and edits outside the dictated range. It does not simulate Accessibility notifications or timers.

`Tests/run_dictionary_matcher_experiment_tests.sh` additionally exercises real negative evidence provenance and confirms phrase/plural changes cannot create negatives.

To change filtering, replace `DictionaryCorrectionEditPolicy.allows`. To remove this policy, remove its calls from the detector and negative resolver; the observer, timers, existing dictionary, and matcher remain independent. The detector retains the separate single-word requirement.
