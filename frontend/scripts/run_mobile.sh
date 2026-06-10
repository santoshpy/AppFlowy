#!/usr/bin/env bash
#
# run_mobile.sh — build the AppFlowy/Teamflowy Rust core for a mobile target and
# launch the Flutter app on it, in one step. Encodes the environment quirks that
# otherwise make a fresh `flutter run` fail (see MOBILE_BUILD.md and the notes below).
#
# Usage:
#   scripts/run_mobile.sh sim            # iOS Simulator (debug)
#   scripts/run_mobile.sh ios            # physical iOS device (debug, stays attached)
#   scripts/run_mobile.sh ios release    # physical iOS device (release, standalone)
#   scripts/run_mobile.sh android        # Android device/emulator (debug)
#
# Normally invoked via cargo-make:
#   cargo make run-ios-sim | run-ios-device | run-android
#
# Overrides (env):
#   FLUTTER_BIN=/path/to/flutter   # force a specific Flutter; otherwise fvm-pinned 3.27.4 is used
#   DEVICE_ID=<id>                 # skip auto-detection and run on this device id
#
set -euo pipefail

TARGET="${1:-sim}"
MODE="${2:-debug}"

# Resolve repo paths relative to this script (frontend/scripts/run_mobile.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${FRONTEND_DIR}/appflowy_flutter"

say() { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. PATH: the protobuf codegen plugin lives in the pub-cache bin dir, which is
#    usually not on PATH. Without it every flowy-* build script panics.
export PATH="${HOME}/.pub-cache/bin:${PATH}"

# ── 2. Flutter: this repo is pinned to 3.27.4 (see .fvmrc / CI). The system Flutter
#    is often newer and fails dependency resolution (leak_tracker conflict), so we
#    drive Flutter through fvm unless the caller overrides FLUTTER_BIN.
if [[ -n "${FLUTTER_BIN:-}" ]]; then
  FLUTTER=("${FLUTTER_BIN}")
elif command -v fvm >/dev/null 2>&1; then
  FLUTTER=(fvm flutter)
else
  FLUTTER=(flutter)
  say "WARNING: fvm not found; using '$(command -v flutter || echo flutter)'. This repo expects Flutter 3.27.4."
fi

# ── 3. protoc-gen-dart health: the Dart snapshot behind protoc-gen-dart goes stale
#    when the Dart SDK updates. A stale snapshot makes the plugin fall back to
#    `dart pub global run`, which prints resolution chatter to stdout and corrupts
#    protoc's output ("Plugin output is unparseable"). Re-activate if unhealthy.
ensure_protoc_gen_dart() {
  local bin="${HOME}/.pub-cache/bin/protoc-gen-dart" out
  if [[ -x "${bin}" ]] && out="$(printf '' | "${bin}" 2>/dev/null)" \
      && ! grep -qiE 'resolving dependencies|downloading packages' <<<"${out}"; then
    return 0
  fi
  say "Refreshing protoc-gen-dart snapshot (stale or missing)…"
  dart pub global deactivate protoc_plugin >/dev/null 2>&1 || true
  dart pub global activate protoc_plugin 21.1.2 >/dev/null
}

# ── 4. Per-target config: cargo-make profile for the Rust core + Flutter flags.
case "${TARGET}" in
  sim)
    CORE_PROFILE="development-ios-arm64-sim"
    CORE_TASK="appflowy-core-dev-ios"
    ;;
  ios)
    if [[ "${MODE}" == "release" ]]; then
      CORE_PROFILE="production-ios-arm64"
    else
      CORE_PROFILE="development-ios-arm64"
    fi
    CORE_TASK="appflowy-core-dev-ios"
    ;;
  android)
    CORE_PROFILE="development-android"
    CORE_TASK="appflowy-core-dev-android"
    ;;
  *)
    die "Unknown target '${TARGET}'. Use: sim | ios | android"
    ;;
esac

FLUTTER_FLAGS=(--debug)
[[ "${MODE}" == "release" ]] && FLUTTER_FLAGS=(--release)

# ── 5. Device selection (override with DEVICE_ID).
detect_device() {
  if [[ -n "${DEVICE_ID:-}" ]]; then echo "${DEVICE_ID}"; return; fi
  case "${TARGET}" in
    sim)
      # First booted simulator; boot one if none is running.
      local udid
      udid="$(xcrun simctl list devices booted -j 2>/dev/null \
        | python3 -c 'import json,sys;ds=json.load(sys.stdin)["devices"];print(next((d["udid"] for v in ds.values() for d in v if d.get("state")=="Booted"),""))')"
      if [[ -z "${udid}" ]]; then
        say "No booted simulator; booting one…" >&2
        udid="$(xcrun simctl list devices available -j \
          | python3 -c 'import json,sys;ds=json.load(sys.stdin)["devices"];print(next((d["udid"] for k,v in ds.items() if "iOS" in k for d in v if "iPhone" in d.get("name","")),""))')"
        [[ -n "${udid}" ]] || die "No available iPhone simulator found."
        xcrun simctl boot "${udid}" >/dev/null 2>&1 || true
        open -a Simulator >/dev/null 2>&1 || true
      fi
      echo "${udid}"
      ;;
    ios)
      "${FLUTTER[@]}" devices --machine 2>/dev/null \
        | python3 -c 'import json,sys;ds=json.load(sys.stdin);print(next((d["id"] for d in ds if str(d.get("targetPlatform","")).startswith("ios") and not d.get("emulator",False)),""))'
      ;;
    android)
      "${FLUTTER[@]}" devices --machine 2>/dev/null \
        | python3 -c 'import json,sys;ds=json.load(sys.stdin);print(next((d["id"] for d in ds if str(d.get("targetPlatform","")).startswith("android")),""))'
      ;;
  esac
}

# ── Run ────────────────────────────────────────────────────────────────────────
say "Target: ${TARGET} (${MODE}) | core profile: ${CORE_PROFILE}"
"${FLUTTER[@]}" --version | head -1 || true

ensure_protoc_gen_dart

say "Building Rust core (${CORE_PROFILE})…"
( cd "${FRONTEND_DIR}" && cargo make --profile "${CORE_PROFILE}" "${CORE_TASK}" )

DEVICE="$(detect_device)"
[[ -n "${DEVICE}" ]] || die "No ${TARGET} device found. Connect/boot one, or pass DEVICE_ID=<id>."

say "Launching on device: ${DEVICE}"
cd "${APP_DIR}"
exec "${FLUTTER[@]}" run -d "${DEVICE}" "${FLUTTER_FLAGS[@]}"
