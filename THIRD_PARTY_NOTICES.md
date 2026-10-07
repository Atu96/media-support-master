# Third-party notices

The bundled ARM `whisper-cli` depends on whisper.cpp/ggml. Their MIT notices are retained in:

- [whisper.cpp notice](build-native/assets/offline-whisper/licenses/whisper.cpp-LICENSE)
- [ggml notice](build-native/assets/offline-whisper/licenses/ggml-LICENSE)

The optional Python refine engine lists dependencies in [requirements.txt](engines/SRT_Refine/requirements.txt). Installing these packages does not change their licenses. Python environments and downloaded models are excluded from this repository.

FFmpeg and legacy tools may be resolved from the user's own installation; this source upload does not include a new FFmpeg binary or a complete external toolchain. Model downloads have their own terms. Before distributing an installer, review every binary/model actually included and preserve its required notices and corresponding source information.

The 0.2.1 Preview 1 DMG bundles the app, the small ARM Whisper executable with the two MIT notices above, and this project's runtime scripts/refine source. It excludes FFmpeg, Python environments, downloaded models, and the custom Motion title. The Whisper executable links to macOS system libraries; no additional local dynamic-library bundle is included.

The project's own code has no selected open-source license. These notices apply only to the named third-party components and are not an app-wide license.

Current development builds additionally bundle the existing **Phu de nen den** Motion title and its preview images. The project owner has confirmed permission to distribute this template. This permission is not an app-wide open-source license. The managed tool release retains the Whisper/ggml MIT notices and excludes models, FFmpeg and Python runtimes.
