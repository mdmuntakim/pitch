#!/usr/bin/env bash
# ============================================================================
# One-command reproducible build of Matchday Eleven for Android.
#
#   bash build/export.sh              # signed arm64-v8a release APK
#   ABI=x86_64 bash build/export.sh   # debug x86_64 APK for smoke tests only
#
# Pinned: Godot 4.5.2-stable editor + matching export templates.
# Release output: build/matchday-eleven-arm64.apk (arm64-v8a only, signed with
# the project's committed signing key in signing/debug.keystore).
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_VERSION="4.5.2-stable"
GODOT_TEMPLATE_DIR="4.5.2.stable"   # Godot's own version string for the templates
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
TEMPLATES_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
TOOLS="${PITCH_TOOLS:-$HOME/.cache/pitch-tools}"
ABI="${ABI:-arm64}"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_DIR"

log() { printf '==> %s\n' "$*"; }

mkdir -p "$TOOLS" build
START_EPOCH=$(date +%s)

# --- engine ----------------------------------------------------------------
if [ ! -x "$TOOLS/godot" ]; then
  log "downloading Godot $GODOT_VERSION editor"
  if [ ! -f "$TOOLS/godot.zip" ]; then
    curl -fsSL -o "$TOOLS/godot.zip" "$GODOT_URL"
  fi
  unzip -o -q "$TOOLS/godot.zip" -d "$TOOLS"
  mv "$TOOLS/Godot_v${GODOT_VERSION}_linux.x86_64" "$TOOLS/godot"
  chmod +x "$TOOLS/godot"
fi
GODOT="$TOOLS/godot"

if [ ! -f "$TEMPLATES_DIR/android_release.apk" ]; then
  log "downloading Godot $GODOT_VERSION export templates (~1.3 GB)"
  if [ ! -f "$TOOLS/templates.tpz" ]; then
    curl -fsSL -o "$TOOLS/templates.tpz" "$TEMPLATES_URL"
  fi
  mkdir -p "$TEMPLATES_DIR"
  rm -rf "$TOOLS/tpz"
  unzip -o -q "$TOOLS/templates.tpz" -d "$TOOLS/tpz"
  mv "$TOOLS/tpz/templates/"* "$TEMPLATES_DIR/"
fi

# --- signing key -----------------------------------------------------------
# The project's public signing key (debug-grade, documented in README).
# CI and local builds both use the committed file.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/signing/debug.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="androiddebugkey"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="android"

# --- generated assets ------------------------------------------------------
# Assets are procedurally generated and deterministic; regenerate when absent.
if [ ! -f assets/audio/crowd_home.wav ] || [ ! -f assets/textures/scoreboard.png ]; then
  log "generating procedural assets (~6 min)"
  command -v python3 >/dev/null || { echo "python3 required"; exit 1; }
  python3 -c "import numpy" 2>/dev/null || pip3 install --quiet numpy
  python3 tools/gen_assets.py
fi

# --- import + tests --------------------------------------------------------
log "importing assets"
"$GODOT" --headless --import > "$TOOLS/import.log" 2>&1 || { tail -40 "$TOOLS/import.log"; exit 1; }

log "running engine tests"
"$GODOT" --headless -s tests/run_tests.gd 2>&1 | tee "$TOOLS/tests.log" | tail -3
grep -q "ALL TESTS PASSED" "$TOOLS/tests.log" || { echo "tests failed"; exit 1; }

# --- export ----------------------------------------------------------------
PRESET="Android arm64"
if [ "$ABI" = "x86_64" ]; then
  # Smoke-test build only. Never published, never shipped.
  sed -i 's|architectures/arm64-v8a=true|architectures/arm64-v8a=false|; s|architectures/x86_64=false|architectures/x86_64=true|' export_presets.cfg
  APK="build/matchday-eleven-x86_64-debug.apk"
  log "exporting Android x86_64 debug APK (smoke tests, not for release)"
  "$GODOT" --headless --export-debug "$PRESET" "$APK" 2>&1 | tail -5
else
  APK="build/matchday-eleven-arm64.apk"
  log "exporting Android arm64 APK"
  "$GODOT" --headless --export-release "$PRESET" "$APK" 2>&1 | tail -5
fi

END_EPOCH=$(date +%s)
log "build time: $((END_EPOCH - START_EPOCH)) s"
log "APK: $(wc -c <"$APK") bytes"
log "APK size: $(du -h "$APK" | cut -f1)"
sha256sum "$APK"
log "ABIs inside the APK:"
unzip -l "$APK" | grep "lib/" | awk '{print $4}' | sort -u
