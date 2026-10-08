# Packaged Japanese alignment

The app retains the original Japanese algorithm in `legacy_core.py`, its UniDic 2.1.2 runtime dictionary, and the repository's force-abut semantics. `japanese_helper.py` supplies a quoted, bundle-relative dictionary path and runs as a frozen ARM helper. It has no host Python, Homebrew, FFmpeg or `Documents/Tools` requirement.

The bundle is pinned by `assets/japanese/tools.lock.json`. Build-time `scripts/lib/prepare_japanese_helper.py` downloads/verifies the archive if the cache is absent, verifies every regular file and runs its self-test. It never runs on user installations. Binary/dictionary files stay outside source Git; the component asset includes the source, licenses and provenance.

## Rebuild inputs

- Official Python 3.14.8 macOS installer: `https://www.python.org/ftp/python/3.14.8/python-3.14.8-macos11.pkg`, SHA256 `507fc086c5c006ff875d344a75b4e67b8fb3c401f1bc4908c6250adb673d4907`. Verify PSF installer signature and extract without installing. Do not use Homebrew Python binaries requiring macOS26 for a macOS15 package.
- PyInstaller 6.22.3; mecab-python3 1.0.12. MeCab/UniDic distributed under their BSD options; full notices accompany the runtime.
- UniDic 2.1.2 compiled runtime files used by the original workflow. Exact hashes are stored in packaged `PROVENANCE.json`. The vendor prebuilt archive is not byte-identical to the Homebrew-compiled files; replacing it requires differential fixtures first.

Freeze on ARM with `--onedir --noupx --target-architecture arm64 --name japanese-helper`, add the exact dictionary as `dictionary`, and supply this directory as the module search path. Use an isolated build environment. Audit every Mach-O for minimum OS <=15 and no absolute Homebrew/system-Python dependency, preserve full notices, then compare all six Japanese fixtures exactly against the original environment. Do not change `legacy_core.py` merely to reduce package size.

`test_japanese_helper.py HELPER LEGACY_CORE LEGACY_PYTHON LEGACY_DICTIONARY` compares text, wrap and timing byte-for-byte, then executes the helper with fresh HOME and a system-only PATH. Set `MSM_JAPANESE_LEGACY_PYTHON` and `MSM_JAPANESE_LEGACY_DICTIONARY` to include this comparison in `test.command`. Ordinary offline QA does not download tools, access Keychain or consume API quota.

The app prepares audio with AVFoundation and uses the already bundled Whisper with the original Japanese max-len=1 settings. Helpers exit after the job; the dictionary is not loaded by idle apps. The 1.62 GB transcription model remains a separate user-selected download. macOS15+ cloud features remain available without offline models; Apple on-device summaries require macOS26+ and runtime availability/language checks. On macOS27 the system default automatically refers to the OS's new model.
