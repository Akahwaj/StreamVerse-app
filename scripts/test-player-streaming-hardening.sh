#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-source}"
FAILED=0

pass() { echo "PASS: $1"; }
fail() { echo "::error::$1"; FAILED=1; }

require_file() {
  local path="$1" label="$2"
  [[ -f "$SOURCE_ROOT/$path" ]] && pass "$label" || fail "$label missing: $path"
}

require_tree_match() {
  local root="$1" pattern="$2" label="$3"
  if [[ -d "$SOURCE_ROOT/$root" ]] && grep -RIEq --include='*.kt' --include='*.java' --include='*.xml' "$pattern" "$SOURCE_ROOT/$root"; then
    pass "$label"
  else
    fail "$label"
  fi
}

require_file_match() {
  local path="$1" pattern="$2" label="$3"
  if [[ -f "$SOURCE_ROOT/$path" ]] && grep -Eq "$pattern" "$SOURCE_ROOT/$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

require_absent_tree_match() {
  local root="$1" pattern="$2" label="$3"
  if [[ -d "$SOURCE_ROOT/$root" ]] && grep -RIEq --include='*.kt' --include='*.java' --include='*.xml' "$pattern" "$SOURCE_ROOT/$root"; then
    fail "$label"
  else
    pass "$label"
  fi
}

PLAYER_ROOT="app/src/main/java/com/nuvio/tv"
SELECTOR="$PLAYER_ROOT/core/player/StreamAutoPlaySelector.kt"
MANIFEST="app/src/main/AndroidManifest.xml"

# Baseline source selection that already exists and must not regress.
require_file "$SELECTOR" "Stream auto-play selector"
require_file_match "$SELECTOR" 'distinctBy\(::streamIdentityKey\)' "Duplicate source suppression"
require_file_match "$SELECTOR" 'isDirectDebrid\(\)' "Direct-debrid preference"
require_file_match "$SELECTOR" 'StreamDebridCacheState\.CACHED' "Cached-debrid awareness"
require_file_match "$SELECTOR" 'qualityValue' "Quality ranking"

# Missing StreamVerse smart-stream layer. These contracts intentionally fail until
# the implementation is present; they define the acceptance target for the next build.
require_tree_match "$PLAYER_ROOT" 'codec|MediaCodec(List|Info)|DecoderCapabilities|CodecCapabilities' "Codec/device-decoder compatibility participates in source selection"
require_tree_match "$PLAYER_ROOT" 'videoSize|cachedSize|folderSize|raw\.size|fileSize|contentLength' "File-size awareness participates in source selection"
require_tree_match "$PLAYER_ROOT" 'bitrate|bandwidth|throughput|networkSpeed|estimatedMbps' "Bitrate/bandwidth awareness participates in source selection"
require_tree_match "$PLAYER_ROOT" 'MediaCodecList|MediaCodecInfo|Build\.(MODEL|MANUFACTURER)|DeviceCapabilities|DeviceProfile' "Actual device capability profile is consulted"
require_tree_match "$PLAYER_ROOT" 'preflight|healthCheck|sourceHealth|HTTP.*HEAD|Range.*bytes=0-|probeStream' "Source health preflight exists"
require_tree_match "$PLAYER_ROOT" 'FailureHistory|recentFailure|failureCooldown|blacklist|quarantine|suppress.*fail|failedSource' "Recent source failures are remembered and temporarily suppressed"
require_tree_match "$PLAYER_ROOT" 'failover|nextCandidate|nextStream|advanceToNext|tryNextSource' "Automatic next-source failover exists"
require_tree_match "$PLAYER_ROOT/ui/screens/player" 'PlayerStallWatchdogPolicy' "Stall watchdog is wired into the internal player"
require_tree_match "$PLAYER_ROOT/ui/screens/player" 'failover|nextCandidate|nextStream|advanceToNext|tryNextSource' "Internal player invokes failover on playback failure/stall"
require_tree_match "$PLAYER_ROOT/ui/screens/player" 'PlayerPlaybackAnalyticsDiagnostics|LastPlaybackDiagnostics' "Playback diagnostics remain wired"
require_tree_match "$PLAYER_ROOT/core/player" 'ExternalPlayerLauncher' "External player fallback remains available"

# Fresh-install policy: deleting StreamVerse must leave no app-restorable state behind.
# Manual user-created backup files are the only allowed persistence mechanism.
require_file "$MANIFEST" "Android manifest"
require_file_match "$MANIFEST" 'android:allowBackup="false"' "Android automatic backup is disabled"
require_file_match "$MANIFEST" 'android:dataExtractionRules="@xml/data_extraction_rules"' "Android 12+ cloud/device-transfer extraction rules are explicit"
require_file_match "$MANIFEST" 'android:fullBackupContent="@xml/backup_rules"' "Android 11-and-lower full-backup rules are explicit"
require_file "app/src/main/res/xml/data_extraction_rules.xml" "Android 12+ no-transfer rules"
require_file "app/src/main/res/xml/backup_rules.xml" "Legacy no-backup rules"
require_file_match "app/src/main/res/xml/data_extraction_rules.xml" '<device-transfer>' "Device-to-device transfer rules are defined"
require_file_match "app/src/main/res/xml/data_extraction_rules.xml" '<exclude[[:space:]]+domain="(root|device_root)"[[:space:]]+path="\."' "Device transfer excludes app root data"
require_file_match "app/src/main/res/xml/backup_rules.xml" '<exclude[[:space:]]+domain="root"[[:space:]]+path="\."' "Legacy backup excludes app root data"
require_absent_tree_match "$PLAYER_ROOT" 'BackupAgent|onRestore\(|restoreAtInstall|autoRestore|automaticRestore' "No hidden automatic restore path exists"

# Manual Backup / Restore is the one intentional persistence escape hatch.
# The archive must be explicit, versioned, encrypted, and user initiated.
require_tree_match "$PLAYER_ROOT" 'StreamVerseBackup|BackupManager|BackupRepository' "Manual StreamVerse backup implementation exists"
require_tree_match "$PLAYER_ROOT" 'exportBackup|createBackup|saveBackup' "Manual backup export action exists"
require_tree_match "$PLAYER_ROOT" 'restoreBackup|importBackup' "Manual restore action exists"
require_tree_match "$PLAYER_ROOT" 'SCHEMA_VERSION|backupVersion|formatVersion' "Backup format is versioned"
require_tree_match "$PLAYER_ROOT" 'AES/GCM|AES.*GCM|GCMParameterSpec' "Backup payload uses authenticated encryption"
require_tree_match "$PLAYER_ROOT" 'PBKDF2|Argon2|scrypt|SecretKeyFactory' "Portable backup key is derived independently of uninstallable app keystore state"
require_tree_match "$PLAYER_ROOT/ui" 'Backup.*Restore|Restore.*Backup|Export.*Backup|Import.*Backup' "Backup and Restore are exposed in Settings UI"
require_tree_match "$PLAYER_ROOT" 'addons|addon.*preferences|playback|history|favorites|tracking|live.?tv|m3u|xmltv' "Backup coverage includes StreamVerse user configuration/state domains"

if (( FAILED != 0 )); then
  echo "::error::Player/streaming/fresh-install acceptance contract failed"
  exit 1
fi

echo "All player, streaming, fresh-install, and manual backup/restore contracts passed."
