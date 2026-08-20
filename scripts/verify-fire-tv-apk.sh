#!/usr/bin/env bash
# verify-fire-tv-apk.sh — APK acceptance gate for the Fire TV build
# Usage: verify-fire-tv-apk.sh <apk_path> <expected_abi> <expected_package> <min_mib> <max_mib>
set -euo pipefail

APK_PATH="${1:?APK path required}"
EXPECTED_ABI="${2:?Expected ABI required}"
EXPECTED_PACKAGE="${3:?Expected package required}"
MIN_MIB="${4:?Minimum MiB required}"
MAX_MIB="${5:?Maximum MiB required}"

SUMMARY_FILE="apk-verification-summary.txt"
SIGNATURE_FILE="apk-signature.txt"
BADGING_FILE="apk-badging.txt"
MANIFEST_FILE="apk-manifest-tree.txt"

pass() { echo "PASS: $*" | tee -a "$SUMMARY_FILE"; }
fail() { echo "FAIL: $*" | tee -a "$SUMMARY_FILE"; FAILED=1; }

FAILED=0

# --- File exists and is readable -----------------------------------------
if [[ ! -f "$APK_PATH" ]]; then
  echo "::error::APK not found: $APK_PATH"
  exit 1
fi

# --- Size check -----------------------------------------------------------
size_bytes=$(stat -c '%s' "$APK_PATH")
size_mib=$(echo "scale=2; $size_bytes / 1048576" | bc)
min_bytes=$(( MIN_MIB * 1048576 ))
max_bytes=$(( MAX_MIB * 1048576 ))

if (( size_bytes >= min_bytes && size_bytes <= max_bytes )); then
  pass "APK size ${size_mib} MiB is within [${MIN_MIB}, ${MAX_MIB}] MiB"
else
  fail "APK size ${size_mib} MiB is outside [${MIN_MIB}, ${MAX_MIB}] MiB"
fi

# --- aapt2 badging -------------------------------------------------------
if command -v aapt2 &>/dev/null; then
  aapt2 dump badging "$APK_PATH" > "$BADGING_FILE" 2>&1 || true

  # Package name
  pkg=$(grep -oP "^package: name='\K[^']+" "$BADGING_FILE" || true)
  if [[ "$pkg" == "$EXPECTED_PACKAGE" ]]; then
    pass "Package name matches: $pkg"
  else
    fail "Package name mismatch: got '$pkg', expected '$EXPECTED_PACKAGE'"
  fi

  # Native ABI
  if grep -qF "native-code: '${EXPECTED_ABI}'" "$BADGING_FILE"; then
    pass "Native ABI ${EXPECTED_ABI} present"
  else
    fail "Native ABI ${EXPECTED_ABI} not found in badging output"
  fi

  # Leanback launcher (Fire TV requirement)
  if grep -qF "uses-feature: name='android.software.leanback'" "$BADGING_FILE"; then
    pass "Leanback feature declared"
  else
    fail "Leanback feature not declared (required for Fire TV)"
  fi
else
  fail "aapt2 not found; badging checks (package name, ABI, leanback) could not run"
fi

# --- aapt manifest dump --------------------------------------------------
if command -v aapt &>/dev/null; then
  aapt list -a "$APK_PATH" > "$MANIFEST_FILE" 2>&1 || true
fi

# --- apksigner / keytool signature check ---------------------------------
if command -v apksigner &>/dev/null; then
  apksigner verify --print-certs "$APK_PATH" > "$SIGNATURE_FILE" 2>&1 || true
  if grep -q "Signer" "$SIGNATURE_FILE"; then
    pass "APK is signed"
  else
    fail "APK does not appear to be signed"
  fi
else
  fail "apksigner not found; signature check could not run"
fi

# --- Result --------------------------------------------------------------
if (( FAILED == 0 )); then
  echo "All APK acceptance checks passed." | tee -a "$SUMMARY_FILE"
else
  echo "::error::One or more APK acceptance checks failed. See $SUMMARY_FILE for details."
  exit 1
fi
