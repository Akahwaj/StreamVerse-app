#!/usr/bin/env bash
# verify-fire-tv-apk.sh — strict acceptance gate for a Fire TV APK.
# Usage: verify-fire-tv-apk.sh <apk_path> <expected_abis> <expected_package> <min_mib> <max_mib>
set -euo pipefail

APK_PATH="${1:?APK path required}"
EXPECTED_ABIS="${2:?Expected ABI list required}"
EXPECTED_PACKAGE="${3:?Expected package required}"
MIN_MIB="${4:?Minimum MiB required}"
MAX_MIB="${5:?Maximum MiB required}"

SUMMARY_FILE="apk-verification-summary.txt"
SIGNATURE_FILE="apk-signature.txt"
BADGING_FILE="apk-badging.txt"
MANIFEST_FILE="apk-manifest.xml"
MANIFEST_CHECK_FILE="apk-manifest-checks.txt"

: > "$SUMMARY_FILE"
FAILED=0
pass() { echo "PASS: $*" | tee -a "$SUMMARY_FILE"; }
fail() { echo "FAIL: $*" | tee -a "$SUMMARY_FILE"; FAILED=1; }

find_sdk_tool() {
  local tool="$1"
  local found=""
  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return 0
  fi
  for sdk_root in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
    [[ -n "$sdk_root" && -d "$sdk_root" ]] || continue
    found=$(find "$sdk_root" -type f -name "$tool" -perm -u+x 2>/dev/null | sort -V | tail -n 1)
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      return 0
    fi
  done
  return 1
}

if [[ ! -f "$APK_PATH" || "${APK_PATH##*.}" != "apk" ]]; then
  echo "::error::Installable .apk not found: $APK_PATH"
  exit 1
fi

if ! unzip -tq "$APK_PATH" >/dev/null; then
  echo "::error::APK ZIP integrity check failed"
  exit 1
fi
pass "APK ZIP structure is valid"

if [[ ! "$MIN_MIB" =~ ^[0-9]+$ || ! "$MAX_MIB" =~ ^[0-9]+$ || "$MIN_MIB" -ge "$MAX_MIB" ]]; then
  echo "::error::Size limits must be whole MiB values with min < max"
  exit 1
fi

size_bytes=$(stat -c '%s' "$APK_PATH")
size_mib=$(awk -v bytes="$size_bytes" 'BEGIN { printf "%.2f", bytes / 1048576 }')
min_bytes=$((MIN_MIB * 1048576))
max_bytes=$((MAX_MIB * 1048576))
if (( size_bytes >= min_bytes && size_bytes <= max_bytes )); then
  pass "APK size ${size_mib} MiB is within [${MIN_MIB}, ${MAX_MIB}] MiB"
else
  fail "APK size ${size_mib} MiB is outside [${MIN_MIB}, ${MAX_MIB}] MiB"
fi

AAPT2=$(find_sdk_tool aapt2 || true)
APKSIGNER=$(find_sdk_tool apksigner || true)
APKANALYZER=$(find_sdk_tool apkanalyzer || true)

if [[ -z "$AAPT2" ]]; then
  fail "aapt2 not found; package and ABI checks did not run"
else
  if "$AAPT2" dump badging "$APK_PATH" > "$BADGING_FILE" 2>&1; then
    pkg=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" "$BADGING_FILE" | head -n 1)
    version_name=$(sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p" "$BADGING_FILE" | head -n 1)
    version_code=$(sed -n "s/^package:.*versionCode='\([^']*\)'.*/\1/p" "$BADGING_FILE" | head -n 1)

    [[ "$pkg" == "$EXPECTED_PACKAGE" ]]       && pass "Package name matches: $pkg"       || fail "Package mismatch: got '$pkg', expected '$EXPECTED_PACKAGE'"

    [[ -n "$version_name" && -n "$version_code" ]]       && pass "Version is $version_name ($version_code)"       || fail "Version name or version code is missing"

    native_line=$(grep "^native-code:" "$BADGING_FILE" | head -n 1 || true)
    actual_abis=$(printf '%s\n' "$native_line" | grep -o "'[^']*'" | tr -d "'" | sort | tr '\n' ' ' | sed 's/ $//' || true)
    expected_abis=$(printf '%s\n' $EXPECTED_ABIS | sort | tr '\n' ' ' | sed 's/ $//')
    if [[ "$actual_abis" == "$expected_abis" ]]; then
      pass "APK contains exactly the expected native ABIs: $EXPECTED_ABIS"
    else
      fail "Native ABI set is not exactly '$EXPECTED_ABIS': ${native_line:-none}"
    fi

    grep -q "^application-label:" "$BADGING_FILE"       && pass "Application label is present"       || fail "Application label is missing"
    grep -q "^application-icon-" "$BADGING_FILE"       && pass "Application icon is present"       || fail "Application icon is missing"
  else
    fail "aapt2 could not inspect APK badging"
  fi
fi

if [[ -z "$APKANALYZER" ]]; then
  fail "apkanalyzer not found; launcher, banner, and feature checks did not run"
elif "$APKANALYZER" manifest print "$APK_PATH" > "$MANIFEST_FILE" 2>/dev/null; then
  python3 - "$MANIFEST_FILE" > "$MANIFEST_CHECK_FILE" <<'PY'
import sys
import xml.etree.ElementTree as ET

ANDROID = "{http://schemas.android.com/apk/res/android}"
root = ET.parse(sys.argv[1]).getroot()
uses_sdk = root.find("uses-sdk")
min_sdk = uses_sdk.get(ANDROID + "minSdkVersion", "") if uses_sdk is not None else ""
app = root.find("application")
if app is None:
    print("launcher_activity=")
    print("launcher_exported=false")
    print("banner=")
    print("leanback_feature=false")
    print("touchscreen_not_required=false")
    print("internet_permission=false")
    print("install_permission=false")
    print("epg_read_permission=false")
    print("epg_write_permission=false")
    print("streamverse_scheme=false")
    raise SystemExit

leanback_feature = False
touchscreen_not_required = False
for feature in root.findall("uses-feature"):
    name = feature.get(ANDROID + "name", "")
    required = feature.get(ANDROID + "required", "true")
    if name == "android.software.leanback":
        leanback_feature = True
    if name == "android.hardware.touchscreen" and required == "false":
        touchscreen_not_required = True

launcher = ""
launcher_exported = False
launcher_banner = ""
streamverse_scheme = False
for tag in ("activity", "activity-alias"):
    for activity in app.findall(tag):
        for intent_filter in activity.findall("intent-filter"):
            actions = {node.get(ANDROID + "name") for node in intent_filter.findall("action")}
            categories = {node.get(ANDROID + "name") for node in intent_filter.findall("category")}
            schemes = {node.get(ANDROID + "scheme") for node in intent_filter.findall("data")}
            if "streamverse" in schemes:
                streamverse_scheme = True
            if (
                "android.intent.action.MAIN" in actions
                and "android.intent.category.LEANBACK_LAUNCHER" in categories
                and not launcher
            ):
                launcher = activity.get(ANDROID + "name", "")
                launcher_exported = activity.get(ANDROID + "exported") == "true"
                launcher_banner = activity.get(ANDROID + "banner", "")

banner = launcher_banner or app.get(ANDROID + "banner", "")
permissions = {
    node.get(ANDROID + "name", "")
    for node in root.findall("uses-permission")
}
print(f"launcher_activity={launcher}")
print(f"launcher_exported={'true' if launcher_exported else 'false'}")
print(f"banner={banner}")
print(f"leanback_feature={'true' if leanback_feature else 'false'}")
print(f"touchscreen_not_required={'true' if touchscreen_not_required else 'false'}")
print(f"internet_permission={'true' if 'android.permission.INTERNET' in permissions else 'false'}")
print(f"install_permission={'true' if 'android.permission.REQUEST_INSTALL_PACKAGES' in permissions else 'false'}")
print(f"epg_read_permission={'true' if 'com.android.providers.tv.permission.READ_EPG_DATA' in permissions else 'false'}")
print(f"epg_write_permission={'true' if 'com.android.providers.tv.permission.WRITE_EPG_DATA' in permissions else 'false'}")
print(f"streamverse_scheme={'true' if streamverse_scheme else 'false'}")
print(f"min_sdk={min_sdk}")
PY

  launcher=$(sed -n 's/^launcher_activity=//p' "$MANIFEST_CHECK_FILE")
  launcher_exported=$(sed -n 's/^launcher_exported=//p' "$MANIFEST_CHECK_FILE")
  banner=$(sed -n 's/^banner=//p' "$MANIFEST_CHECK_FILE")
  leanback_feature=$(sed -n 's/^leanback_feature=//p' "$MANIFEST_CHECK_FILE")
  touchscreen_not_required=$(sed -n 's/^touchscreen_not_required=//p' "$MANIFEST_CHECK_FILE")
  internet_permission=$(sed -n 's/^internet_permission=//p' "$MANIFEST_CHECK_FILE")
  install_permission=$(sed -n 's/^install_permission=//p' "$MANIFEST_CHECK_FILE")
  epg_read_permission=$(sed -n 's/^epg_read_permission=//p' "$MANIFEST_CHECK_FILE")
  epg_write_permission=$(sed -n 's/^epg_write_permission=//p' "$MANIFEST_CHECK_FILE")
  streamverse_scheme=$(sed -n 's/^streamverse_scheme=//p' "$MANIFEST_CHECK_FILE")
  min_sdk=$(sed -n 's/^min_sdk=//p' "$MANIFEST_CHECK_FILE")

  [[ -n "$launcher" ]]     && pass "Leanback launcher activity resolves: $launcher"     || fail "No MAIN + LEANBACK_LAUNCHER activity found"
  [[ "$launcher_exported" == "true" ]]     && pass "Leanback launcher activity is exported"     || fail "Leanback launcher activity is not exported"
  [[ -n "$banner" ]]     && pass "TV banner resource is declared: $banner"     || fail "TV banner resource is missing"
  [[ "$leanback_feature" == "true" ]]     && pass "Leanback feature is declared"     || fail "android.software.leanback feature is missing"
  [[ "$touchscreen_not_required" == "true" ]]     && pass "Touchscreen is explicitly not required"     || fail "android.hardware.touchscreen must be declared required=false"
  [[ "$internet_permission" == "true" ]]     && pass "Network access is declared for web and streaming"     || fail "android.permission.INTERNET is missing"
  [[ "$install_permission" == "true" ]]     && pass "Update installer permission is declared"     || fail "android.permission.REQUEST_INSTALL_PACKAGES is missing"
  [[ "$epg_read_permission" == "true" && "$epg_write_permission" == "true" ]]     && pass "Android TV EPG permissions are declared"     || fail "Android TV EPG permissions are incomplete"
  [[ "$streamverse_scheme" == "true" ]]     && pass "StreamVerse web/deep-link scheme is declared"     || fail "streamverse deep-link scheme is missing"
  [[ "$min_sdk" =~ ^[0-9]+$ && "$min_sdk" -le 30 ]]     && pass "Minimum SDK $min_sdk is compatible with Fire OS 8"     || fail "Minimum SDK '${min_sdk:-unknown}' is not confirmed compatible with Fire OS 8"
else
  fail "apkanalyzer could not decode the merged manifest"
fi

if [[ -z "$APKSIGNER" ]]; then
  fail "apksigner not found; signature verification did not run"
elif "$APKSIGNER" verify --verbose --print-certs "$APK_PATH" > "$SIGNATURE_FILE" 2>&1; then
  if grep -Eq "Verified using v2 scheme.*true|Verified using v3 scheme.*true|Verified using v4 scheme.*true" "$SIGNATURE_FILE"; then
    pass "APK signature verifies with a modern signing scheme"
  else
    fail "APK signature lacks a verified v2/v3/v4 signing scheme"
  fi
else
  fail "apksigner verification failed"
fi

if (( FAILED == 0 )); then
  echo "All Fire TV APK acceptance checks passed." | tee -a "$SUMMARY_FILE"
else
  echo "::error::One or more Fire TV APK acceptance checks failed."
  exit 1
fi
