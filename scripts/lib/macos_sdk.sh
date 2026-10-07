#!/bin/bash
# Select a build SDK without changing the user's xcode-select setting.
msm_macos_sdk() {
    if [[ -n "${MSM_MACOS_SDK_PATH:-}" ]]; then
        [[ -d "$MSM_MACOS_SDK_PATH" ]] || { echo "Missing MSM_MACOS_SDK_PATH" >&2; return 1; }
        printf '%s\n' "$MSM_MACOS_SDK_PATH"
        return
    fi
    local selected version parent candidate
    selected="$(xcrun --show-sdk-path)"
    version="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$selected/SDKSettings.plist")"
    # Standalone CLT 27 can omit SwiftUIMacros. Preserve this app's tested
    # property-wrapper semantics with an installed 26 SDK when available.
    if [[ "${version%%.*}" -ge 27 ]]; then
        parent="$(dirname "$selected")"
        for candidate in 26.5 26.4 26.3 26.2 26.1 26.0 26; do
            if [[ -d "$parent/MacOSX$candidate.sdk" ]]; then
                printf '%s\n' "$parent/MacOSX$candidate.sdk"
                return
            fi
        done
    fi
    printf '%s\n' "$selected"
}
