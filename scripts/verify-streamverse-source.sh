#!/usr/bin/env bash
# Static source gate for the StreamVerse Fire TV distribution.
# Usage: verify-streamverse-source.sh <patched_android_source>
set -euo pipefail

SOURCE_ROOT="${1:?Patched Android source directory required}"
REPORT_FILE="${2:-streamverse-source-audit.txt}"
FAILED=0

: > "$REPORT_FILE"

pass() {
  printf 'PASS: %s\n' "$*" | tee -a "$REPORT_FILE"
}

warn() {
  printf 'WARN: %s\n' "$*" | tee -a "$REPORT_FILE"
}

fail() {
  printf 'FAIL: %s\n' "$*" | tee -a "$REPORT_FILE"
  FAILED=1
}

require_file() {
  local relative_path="$1"
  local description="$2"
  if [[ -f "$SOURCE_ROOT/$relative_path" ]]; then
    pass "$description: $relative_path"
  else
    fail "$description is missing: $relative_path"
  fi
}

require_match() {
  local relative_path="$1"
  local pattern="$2"
  local description="$3"
  if [[ -f "$SOURCE_ROOT/$relative_path" ]] && grep -Eq "$pattern" "$SOURCE_ROOT/$relative_path"; then
    pass "$description"
  else
    fail "$description"
  fi
}

if [[ ! -d "$SOURCE_ROOT/app/src/main" ]]; then
  echo "::error::Android source tree not found: $SOURCE_ROOT"
  exit 1
fi

printf 'StreamVerse source audit\n' >> "$REPORT_FILE"
printf 'Source: %s\n\n' "$SOURCE_ROOT" >> "$REPORT_FILE"

# Native TV UI. StreamVerse uses Jetpack Compose, so a standalone CSS file is
# not expected for the Fire TV layout.
require_file "app/src/main/java/com/nuvio/tv/ui/screens/home/HomeScreen.kt" "Home screen"
require_file "app/src/main/java/com/nuvio/tv/ui/navigation/Screen.kt" "Navigation model"
require_file "app/src/main/java/com/nuvio/tv/ui/components/SidebarNavigation.kt" "D-pad sidebar navigation"
require_file "app/src/main/java/com/nuvio/tv/ui/components/ContentCard.kt" "Poster/content card"
require_file "app/src/main/java/com/nuvio/tv/ui/theme/Theme.kt" "Compose theme"
require_file "app/src/main/java/com/nuvio/tv/ui/theme/Color.kt" "Compose colors"
require_file "app/src/main/java/com/nuvio/tv/ui/theme/SpacingTokens.kt" "Layout spacing tokens"
require_file "app/src/main/res/values/themes.xml" "Android theme resources"
require_file "app/src/main/res/values/colors.xml" "Android color resources"
require_file "app/src/main/res/layout/exo_player_view.xml" "Media3 player layout"
require_file "app/src/main/res/layout/trailer_player_view.xml" "Trailer player layout"

compose_screen_count=$(find "$SOURCE_ROOT/app/src/main/java/com/nuvio/tv/ui/screens" -type f -name '*.kt' | wc -l | tr -d ' ')
if (( compose_screen_count >= 20 )); then
  pass "Compose UI screen tree is populated (${compose_screen_count} Kotlin files)"
else
  fail "Compose UI screen tree is unexpectedly small (${compose_screen_count} Kotlin files)"
fi

resource_count=$(find "$SOURCE_ROOT/app/src/main/res" -type f | wc -l | tr -d ' ')
if (( resource_count >= 50 )); then
  pass "Android UI resources are populated (${resource_count} files)"
else
  fail "Android UI resources are unexpectedly small (${resource_count} files)"
fi

# Embedded web configuration UI. Its HTML, CSS, and JavaScript are intentionally
# compiled from Kotlin strings rather than stored as standalone .css/.js files.
for web_page in AddonWebPage RepositoryWebPage DebridFormatterWebPage StreamBadgeWebPage; do
  require_file "app/src/main/java/com/nuvio/tv/core/server/${web_page}.kt" "Embedded web page ${web_page}"
done
require_match "app/src/main/java/com/nuvio/tv/core/server/AddonWebPage.kt" '<!DOCTYPE html>' "Embedded add-on page contains HTML"
require_match "app/src/main/java/com/nuvio/tv/core/server/AddonWebPage.kt" '<style>' "Embedded add-on page contains CSS"
require_match "app/src/main/java/com/nuvio/tv/core/server/AddonWebPage.kt" '<script>' "Embedded add-on page contains JavaScript"

standalone_css_count=$(find "$SOURCE_ROOT/app/src" -type f \( -name '*.css' -o -name '*.scss' -o -name '*.sass' -o -name '*.less' \) | wc -l | tr -d ' ')
if (( standalone_css_count == 0 )); then
  pass "No standalone CSS is required by the native Compose UI; embedded web CSS is present"
else
  pass "Standalone web style assets are present (${standalone_css_count} files)"
fi

# Add-on compatibility. Standard Stremio manifest resources and Nuvio's full
# local/plugin distribution must remain wired into the same build.
require_file "app/src/main/java/com/nuvio/tv/data/remote/dto/AddonManifestDto.kt" "Stremio manifest model"
require_file "app/src/main/java/com/nuvio/tv/data/remote/api/AddonApi.kt" "Stremio add-on HTTP API"
require_file "app/src/main/java/com/nuvio/tv/data/mapper/AddonMapper.kt" "Stremio manifest mapper"
require_file "app/src/main/java/com/nuvio/tv/data/repository/AddonRepositoryImpl.kt" "Installed add-on repository"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/addon/AddonManagerScreen.kt" "TV add-on manager"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/addon/AddonManagerViewModel.kt" "Add-on URL and manifest controller"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/addon/AddonManagerViewModel.kt" 'stremio://' "Stremio deep-link add-on URLs are normalized"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/addon/AddonManagerViewModel.kt" 'manifest.json' "Stremio manifest URLs are recognized"
require_file "app/src/main/java/com/nuvio/tv/domain/repository/CatalogRepository.kt" "Add-on catalog resources"
require_file "app/src/main/java/com/nuvio/tv/domain/repository/MetaRepository.kt" "Add-on metadata resources"
require_file "app/src/main/java/com/nuvio/tv/domain/repository/SubtitleRepository.kt" "Add-on subtitle resources"
require_file "app/src/main/java/com/nuvio/tv/domain/repository/StreamRepository.kt" "Add-on stream resources"
require_file "app/src/full/java/com/nuvio/tv/core/plugin/PluginManager.kt" "Nuvio/local plugin manager"
require_file "app/src/full/java/com/nuvio/tv/core/plugin/cloudstream/ExternalExtensionRunner.kt" "Nuvio CloudStream-compatible extension runner"
require_file "app/src/main/java/com/nuvio/tv/core/plugin/PluginSafety.kt" "Community plugin safety rules"
require_file "app/src/main/java/com/nuvio/tv/data/local/PluginDataStore.kt" "Community plugin repository storage"
require_file "app/src/main/java/com/nuvio/tv/core/server/RepositoryWebPage.kt" "Web repository manager for open-source plugins"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/plugin/PluginScreen.kt" "Nuvio plugin manager UI"
require_match "app/build.gradle.kts" 'FEATURE_PLUGINS_ENABLED.*true' "Nuvio/local plugins are enabled in the full flavor"

# Live playback compatibility. This validates HLS/M3U playback and Android TV
# EPG integration; it does not claim a standalone XMLTV/Xtream library manager.
require_file "app/src/main/java/com/nuvio/tv/ui/screens/stream/StreamScreen.kt" "Stream selection screen"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" "Player media-source factory"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" 'APPLICATION_M3U8' "HLS MIME handling is compiled"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" 'm3u8.*m3u|m3u.*m3u8' "M3U/M3U8 URL detection is compiled"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" 'APPLICATION_MPD' "MPEG-DASH playback is compiled"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" 'APPLICATION_SS' "Smooth Streaming playback is compiled"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" 'VIDEO_MP4' "MP4 progressive playback is compiled"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" 'VIDEO_MATROSKA' "MKV/Matroska playback is compiled"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerMediaSourceFactory.kt" 'setDefaultRequestProperties' "Per-stream HTTP request headers are supported"
require_file "app/src/main/java/com/nuvio/tv/core/player/ExternalPlayerLauncher.kt" "External-player handoff"
require_file "app/src/main/java/com/nuvio/tv/core/torrent/TorrentService.kt" "Torrent/TorrServer playback service"
require_file "app/src/main/java/com/nuvio/tv/core/torrent/TorrServerBinary.kt" "Bundled TorrServer lifecycle"
require_match "app/src/main/AndroidManifest.xml" 'READ_EPG_DATA' "Android TV EPG read permission is declared"
require_match "app/src/main/AndroidManifest.xml" 'WRITE_EPG_DATA' "Android TV EPG write permission is declared"

if rg -q -i 'xmltv|xtream' "$SOURCE_ROOT/app/src/main" -g '*.kt' -g '*.xml'; then
  pass "XMLTV or Xtream source support is present"
else
  warn "No standalone XMLTV/Xtream channel-library module is present; current Live TV support is stream/HLS based"
fi

# Unified playback-health diagnostics. These hooks identify startup stalls,
# rebuffer points, buffered position, load failures, bandwidth, decoder issues,
# and torrent peer/speed state without exposing full credential-bearing URLs.
require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerLoadingDiagnostics.kt" "Startup loading diagnostics"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerPlaybackAnalyticsDiagnostics.kt" "Unified playback analytics diagnostics"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerStallWatchdogPolicy.kt" "Stalled-buffer recovery policy"
require_file "app/src/main/java/com/nuvio/tv/ui/screens/player/LastPlaybackDiagnostics.kt" "On-device last-playback diagnostics"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerPlaybackAnalyticsDiagnostics.kt" 'rebuffer_start' "Rebuffer start points are recorded"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerPlaybackAnalyticsDiagnostics.kt" 'rebuffer_end' "Rebuffer recovery and duration are recorded"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerPlaybackAnalyticsDiagnostics.kt" 'bufferedPositionMs' "Buffered and playback positions are recorded"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerPlaybackAnalyticsDiagnostics.kt" 'bandwidth_estimate' "Bandwidth estimates are recorded"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerPlaybackAnalyticsDiagnostics.kt" 'load_error' "HTTP/media load failures are recorded"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerRuntimeControllerTorrent.kt" 'torrentDownloadSpeed' "Torrent speed and peer health are exposed to diagnostics"
require_match "app/src/main/java/com/nuvio/tv/ui/screens/player/PlayerLoadingDiagnostics.kt" 'safePlaybackRawHost' "Diagnostic startup logs redact full stream URLs"

# Automatic update client. The full flavor checks GitHub Releases and can
# download/install the stable-signed ARM64 asset produced by the release job.
require_file "app/src/full/java/com/nuvio/tv/updater/UpdateRepository.kt" "GitHub release update repository"
require_file "app/src/full/java/com/nuvio/tv/updater/UpdateViewModel.kt" "Automatic update UI state"
require_file "app/src/full/java/com/nuvio/tv/updater/ApkDownloader.kt" "APK update downloader"
require_file "app/src/full/java/com/nuvio/tv/updater/ApkInstaller.kt" "APK update installer"
require_match "app/build.gradle.kts" 'GITHUB_OWNER.*Akahwaj' "Updater owner points to Akahwaj"
require_match "app/build.gradle.kts" 'GITHUB_REPO.*StreamVerse-app' "Updater repository points to StreamVerse-app"
require_match "app/build.gradle.kts" 'FEATURE_IN_APP_UPDATES_ENABLED.*true' "In-app updates are enabled for the full flavor"
require_match "app/src/main/AndroidManifest.xml" 'REQUEST_INSTALL_PACKAGES' "APK installer permission is declared"

# StreamVerse identity and launcher contract.
require_match "app/build.gradle.kts" 'applicationId[[:space:]]*=[[:space:]]*"com\.akahwaj\.streamverse"' "StreamVerse package ID is configured"
require_match "app/src/main/res/values/strings.xml" '<string name="app_name">StreamVerse</string>' "StreamVerse application label is configured"
require_match "app/src/main/AndroidManifest.xml" 'android\.intent\.category\.LEANBACK_LAUNCHER' "Leanback launcher category is declared"
require_match "app/src/main/AndroidManifest.xml" 'android:banner=' "TV banner resource is declared"
require_match "app/src/main/AndroidManifest.xml" 'android:scheme="streamverse"' "StreamVerse deep-link scheme is declared"

if (( FAILED == 0 )); then
  printf '\nAll required StreamVerse source checks passed.\n' | tee -a "$REPORT_FILE"
else
  echo "::error::One or more StreamVerse source checks failed."
  exit 1
fi
