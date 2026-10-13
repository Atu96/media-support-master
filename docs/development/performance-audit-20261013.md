# Runtime review — 2026-10-13

## Implemented

- **Word timing lookup:** the subtitle formatter previously filtered every word for every provider segment. One immutable interval index now uses binary bounds on ordered valid timestamps and checks only the relevant slice. Provider order, inclusive ±0.04s tolerance and invalid/unsorted fallback are preserved. This removes repeated full-list scans; it does not change recognition or send additional API requests.
- **Waveform lifecycle:** the workspace owns/cancels the active load and checks media/UUID before applying it. Cancellation propagates into the utility decode worker and releases AVAssetReader. Canceled work does not become a successful cache result.
- **QC lifecycle:** initial analysis uses the same background/debounce path as later updates. Cancellation reaches the worker and the analyzer checks between cues. Glyph measurement no longer runs synchronously over every cue when the workspace first appears.
- **One main app:** the installer builds a release-channel app with embedded Runtime, helpers and notices; validates native fixtures in a disposable copy; verifies signature/hash before replacement; checks exact Applications startup; then removes the legacy TEST bundle. Compatibility build commands delegate to this installer. It retains one previous main app for rollback and preserves user data outside the bundle.
- **Maziao catalog:** both shared and account-owned voice endpoints are paginated and merged by ID, preferring owned metadata. Both pickers expose voices across models with model labels. The observed catalog spelling `vietten_speech` resolves to the provider configuration's `vieten_speech` for selection; raw metadata stays intact. A GET-only check using the updated decoder/workflow found 200 unique voices, two owned voices and one Quân Anh search match. No synthesis was performed for these voices.

## Existing controls retained

Waveform keeps reduced peaks/RMS rather than PCM and a three-item process cache. OCR uses one bounded worker/cropped frames/static-image reuse. Layout is cancellable and debounced, with Core Text and Japanese invariants. Cloud dubbing retains bounded remote/I/O concurrency, cache reuse and known-task recovery. These limits should be changed only with representative measurements.

## Further work worth measuring

1. Profile long real projects during drag/playback and font/QC changes; isolate SwiftUI recomputation or allocations before refactoring the large workspace.
2. Measure export stages and move remaining deprecated AVFoundation calls in a separate change with real codec fixtures.
3. Expand sanitized Groq/Google/ElevenLabs response fixtures and real multilingual recognition/layout evaluation. Synthetic tests cannot certify provider accuracy, voice quality or latency.
4. Consider separating test-only launch hooks from production compilation later; the installed release channel currently ignores them.

These are broader review opportunities, not measured regressions. No claim of a whole-app speedup percentage or reduced cloud-server time is made. The initial runtime gate passed 102 core cases; the latest dubbing refactor gate passes 109. Native/package/startup validation is recorded in the current checkpoint.

## Refactor review after the Maziao catalog fix

Review scope: the mapped dubbing/session/settings/catalog/playback owners and their direct call sites. The user subsequently authorized all three items, main-app installation and Git publication. The implementation below passes 109 core tests, native groups/24 XML checks and 737 localization keys across five locales. The packaged comparison, speech-language, dubbing/context and fit-export fixtures also pass without Keychain/API access. This is not a full-app profiler run; the current installed build and publication checkpoint are recorded in the canonical checkpoint.

### 1. Give provider refreshes explicit task and credential ownership

**Implemented: correctness when changing keys during refresh.** The baseline session published metadata without a refresh generation check; clearing a catalog did not invalidate in-flight work, and loading guards could drop the replacement refresh. Maziao reloaded credentials between pages. Delayed fake clients now reproduce late success/error scenarios with cancellation deliberately ignored, without switching real accounts.

`DubbingProviderCoordinator` now owns presence, catalog and usage behind injectable clients. `DubbingRefreshCoordinator` owns coalesced tasks and result generations. Save/delete invalidate catalog and usage before credential I/O and block new metadata requests during mutation. Late success, error and loading callbacks cannot update the new state. Maziao captures one key per paginated catalog. The credential actor rejects stale/coalesced reads after mutation. Live usage adapters defer persistence to accepted results; render completion uses the same usage owner. Secrets remain in memory and Keychain, never in snapshots/logs/preferences. The session forwards observable state and keeps selection behavior.

Verified with delayed fake responses for all three online catalogs and both cloud usage services: A starts, B is saved, A completes last; only B is accepted/persisted. Deletion while loading and an old failure after new success preserve the newest state. Existing pure paging cancellation checks still pass. No paid API tests are used.

### 2. Prepare playback cue data when it changes

**Implemented: avoid repeated work on the main thread.** The preview clock updates at 30 Hz. The baseline session mapped/sorted the rendered dictionary on each synchronization and the player filtered the full result. That work is now prepared outside clock updates; no claim of real-project responsiveness gain is made without profiling.

`DubbingPlaybackSnapshotCache` caches the sorted effective clips. Both rendered-clip and manual-rate mutations invalidate it; the next read rebuilds it once. Lane, preview and export share the snapshot. Its immutable start/prefix-maximum-end lookup examines the candidate interval slice and retains every active overlapping clip, including a long earlier clip. Invalid/unordered timestamps fall back to the original filter.

Pure checks cover 2,000 overlapping clips plus a long preceding clip, exact boundaries, arbitrary forward/backward lookup and unordered fallback. A 5,000-cue fixture performs 3,000 clock queries with one sorted rebuild; rate/retime/delete/clear invalidate correctly. Packaged session fixtures keep reindex/render completion, manual rate/refit, paragraph deletion and latest timing semantics. These prove parity and less repeated preparation, not a CPU percentage, cloud latency improvement or long real-video benchmark.

### 3. Separate session responsibilities by lifecycle

**Implemented: separate lifecycle owners.** The baseline 1,345-line session combined provider metadata and render/cache task handles; Settings independently owned usage refresh state. The provider coordinator above now owns metadata lifecycle. `DubbingJobLifecycle` owns render task/generation/cancellation with stale-finish protection. `DubbingCacheCoordinator` owns the disk store and independent load/merge/usage slots, including cancellable background usage publication. Clearing cache cancels its readers before deletion. Session state remains the facade for cue reconciliation, progress presentation and export intent, preserving transactional editing and avoiding a large render-algorithm rewrite.

Injectable catalog/credential clients now test complete refresh ownership. Pure snapshot types have their own domain file; provider-specific schemas/selection rules retain their owners. Native session checks preserve generation cancellation, remote concurrency, speech reuse/cache identities, manual rates and paragraph reindex/deletion/latest timing; fit export retains complete long/short audio. The established Japanese subtitle path and paid submit schema are unchanged.

### Lower priority

The voice picker currently groups/sorts for both filtered content and its unfiltered summary. Precomputing this projection may help very large catalogs, but the observed 200-voice catalog does not establish a performance problem. Splitting provider models/decoders into separate files or excluding test launch hooks from release compilation can improve organization later; neither warrants a broad rewrite now.

All three scoped changes are implemented. The full offline gate passes 109 core cases and the main installer now requires packaged no-key dubbing/context/fit-export fixtures as well as comparison and speech-language checks. Keep further profiling and optional extractions separate from this verified change.
