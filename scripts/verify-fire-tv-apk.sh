#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 5 ]]; then
  echo "usage: verify-fire-tv-apk.sh APK EXPECTED_ABI [EXPECTED_PACKAGE] [MIN_MIB] [MAX_MIB]" >&2
  exit 2
fi

apk=$1
expected_abi=$2
expected_package=${3:-}
min_mib=${4:-5}
max_mib=${5:-250}

fail() { echo "::error::$*" >&2; exit 1; }

[[ -f "$apk" && "$apk" == *.apk ]] || fail "Expected one APK file"
unzip -tq "$apk" >/dev/null || fail "APK is not a valid ZIP archive"

bytes=$(wc -c < "$apk")
mib=$(( (bytes + 1048575) / 1048576 ))
(( mib >= min_mib && mib <= max_mib )) ||
  fail "APK size ${mib} MiB is outside the allowed ${min_mib}-${max_mib} MiB range"

abis=$(unzip -Z1 "$apk" | sed -n 's#^lib/\([^/]*\)/.*#\1#p' | sort -u | paste -sd, -)
[[ ",$abis," == *",$expected_abi,"* ]] ||
  fail "Expected ABI $expected_abi; found ${abis:-none}"
[[ "$abis" != *,* ]] ||
  fail "Device-specific artifact contains multiple native ABIs: $abis"

build_tools=$(find "${ANDROID_HOME:?ANDROID_HOME is required}/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)
[[ -n "$build_tools" ]] || fail "Android SDK Build Tools not found"
aapt2="$build_tools/aapt2"
apksigner="$build_tools/apksigner"
[[ -x "$aapt2" && -x "$apksigner" ]] || fail "aapt2 or apksigner is unavailable"

"$apksigner" verify --verbose --print-certs "$apk" > apk-signature.txt ||
  fail "APK signature verification failed"

badging=$("$aapt2" dump badging "$apk")
printf '%s\n' "$badging" > apk-badging.txt
package=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$badging" | head -1)
[[ -n "$package" ]] || fail "Package ID was not found"
[[ -z "$expected_package" || "$package" == "$expected_package" ]] ||
  fail "Expected package $expected_package; found $package"

grep -q "^launchable-activity:" <<<"$badging" || fail "Standard launcher activity is missing"
grep -q "^leanback-launcher-activity:" <<<"$badging" || fail "Leanback launcher activity is missing"
grep -q "^application-label:" <<<"$badging" || fail "Application label is missing"
grep -q "^application-icon-" <<<"$badging" || fail "Application icon is missing"

xmltree=$("$aapt2" dump xmltree "$apk" AndroidManifest.xml)
printf '%s\n' "$xmltree" > apk-manifest-tree.txt
grep -q "android:banner" <<<"$xmltree" || fail "Fire TV banner is missing"
if grep -q "android.hardware.touchscreen" <<<"$badging" &&
   ! grep -q "uses-feature-not-required:'android.hardware.touchscreen'" <<<"$badging"; then
  fail "Touchscreen is required; Fire TV apps must not require it"
fi

{
  echo "apk=$(basename "$apk")"
  echo "size_mib=$mib"
  echo "abi=$abis"
  echo "package=$package"
  echo "launcher=present"
  echo "leanback_launcher=present"
  echo "banner=present"
  echo "signature=verified"
} | tee apk-verification-summary.txt
