# Runtime review — 2026-10-13

## Implemented

- **Word timing lookup:** the subtitle formatter previously filtered every word for every provider segment. One immutable interval index now uses binary bounds on ordered valid timestamps and checks only the relevant slice. Provider order, inclusive ±0.04s tolerance and invalid/unsorted fallback are preserved. This removes repeated full-list scans; it does not change recognition or send additional API requests.
- **Waveform lifecycle:** the workspace owns/cancels the active load and checks media/UUID before applying it. Cancellation propagates into the utility decode worker and releases AVAssetReader. Canceled work does not become a successful cache result.
- **QC lifecycle:** initial analysis uses the same background/debounce path as later updates. Cancellation reaches the worker and the analyzer checks between cues. Glyph measurement no longer runs synchronously over every cue when the workspace first appears.
- **One main app:** the installer builds a release-channel app with embedded Runtime, helpers and notices; validates native fixtures in a disposable copy; verifies signature/hash before replacement; checks exact Applications startup; then removes the legacy TEST bundle. Compatibility build commands delegate to this installer. It retains one previous main app for rollback and preserves user data outside the bundle.

## Existing controls retained

Waveform keeps reduced peaks/RMS rather than PCM and a three-item process cache. OCR uses one bounded worker/cropped frames/static-image reuse. Layout is cancellable and debounced, with Core Text and Japanese invariants. Cloud dubbing retains bounded remote/I/O concurrency, cache reuse and known-task recovery. These limits should be changed only with representative measurements.

## Further work worth measuring

1. Profile long real projects during drag/playback and font/QC changes; isolate SwiftUI recomputation or allocations before refactoring the large workspace.
2. Measure export stages and move remaining deprecated AVFoundation calls in a separate change with real codec fixtures.
3. Expand sanitized Groq/Google/ElevenLabs response fixtures and real multilingual recognition/layout evaluation. Synthetic tests cannot certify provider accuracy, voice quality or latency.
4. Consider separating test-only launch hooks from production compilation later; the installed release channel currently ignores them.

These are review opportunities, not measured regressions. No claim of a whole-app speedup percentage or reduced cloud-server time is made. Core QA includes 102 passing cases, interval parity and deterministic worker-cancellation checks; native/package/startup validation is recorded in the current checkpoint.
