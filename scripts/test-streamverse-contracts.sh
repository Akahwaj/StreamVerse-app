#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-source}"
FAILED=0

fail() {
  echo "::error::$1"
  FAILED=1
}

pass() {
  echo "PASS: $1"
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ -f "$SOURCE_ROOT/$path" ]]; then
    pass "$label"
  else
    fail "$label missing: $path"
  fi
}

require_match() {
  local path="$1"
  local pattern="$2"
  local label="$3"
  if [[ -f "$SOURCE_ROOT/$path" ]] && grep -Eq "$pattern" "$SOURCE_ROOT/$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

# Keep this script deliberately contract-focused. The broader source audit
# verifies the complete StreamVerse feature surface; these assertions protect
# the playback decisions that must not silently disappear from the default APK.
require_file "app/src/main/java/com/nuvio/tv/core/player/StreamAutoPlaySelector.kt" "Auto-play selector"
require_match "app/src/main/java/com/nuvio/tv/core/player/StreamAutoPlaySelector.kt" 'distinctBy\(::streamIdentityKey\)' "Duplicate stream removal is active"
require_match "app/src/main/java/com/nuvio/tv/core/player/StreamAutoPlaySelector.kt" 'compareByDescending<Stream> \{ it\.isDirectDebrid\(\) \}' "Direct debrid streams receive first ranking preference"
require_match "app/src/main/java/com/nuvio/tv/core/player/StreamAutoPlaySelector.kt" 'thenByDescending \{ it\.getStreamUrl\(\) != null \}' "Direct URL streams receive ranking preference"
require_match "app/src/main/java/com/nuvio/tv/core/player/StreamAutoPlaySelector.kt" 'StreamDebridCacheState\.CACHED' "Cached debrid state participates in ranking"
require_match "app/src/main/java/com/nuvio/tv/core/player/StreamAutoPlaySelector.kt" 'thenByDescending \{ it\.qualityValue \}' "Quality participates in source ranking"

require_file "app/src/main/java/com/nuvio/tv/ui/screens/settings/EssentialPlaybackSettingsContent.kt" "Essential playback settings"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/settings/EssentialPlaybackSettingsContent.kt" 'PlayerPreference\.INTERNAL' "Internal player choice is exposed"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/settings/EssentialPlaybackSettingsContent.kt" 'PlayerPreference\.EXTERNAL' "External player choice is exposed"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/settings/EssentialPlaybackSettingsContent.kt" 'PlayerPreference\.ASK_EVERY_TIME' "Ask-every-time player choice is exposed"

require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" "Internal player media-source factory"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerStallWatchdogPolicy.kt" "Stalled-buffer recovery policy"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerPlaybackAnalyticsDiagnostics.kt" "Playback health analytics"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/LastPlaybackDiagnostics.kt" "Recent playback failure diagnostics"
require_file "app/src/main/java/com/nuvio/tv/core/player/ExternalPlayerLauncher.kt" "External-player fallback integration"

# Community add-on / provider / Adult gate contracts that feed playback.
require_match "app/src/main/java/com/nuvio/tv/core/server/AddonWebPage.kt" 'configureUrl' "Provider configuration routing remains available"
require_match "app/src/main/java/com/nuvio/tv/core/server/AddonWebPage.kt" 'nsfw=exclude' "Community directory remains safe by default"
require_match "app/src/main/java/com/nuvio/tv/core/server/AddonWebPage.kt" 'nsfw=only' "Adult directory remains isolated"
require_match "app/src/main/java/com/nuvio/tv/core/server/AddonWebPage.kt" 'streamverseAdultConfirmed' "Adult age acknowledgement remains session-scoped"

if (( FAILED != 0 )); then
  echo "::error::StreamVerse mandatory contract validation failed"
  exit 1
fi

echo "All mandatory StreamVerse contracts passed."
