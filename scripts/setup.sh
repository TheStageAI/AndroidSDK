#!/usr/bin/env bash
#
# One-time host setup for the TheStage Android SDK distribution.
#
# What it does (by default):
#   1. Symlinks the two prebuilt AARs (TheStageCore + the ONNX
#      Runtime AAR) into the Flutter plugin's android/libs/, so both
#      the plugin and the example apps resolve them from one place.
#   2. Copies the four Genie/QNN QAIRT runtime libs into the plugin's
#      jniLibs/arm64-v8a/ (only when $QAIRT is set — see below).
#   3. Bootstraps secrets.json from secrets.example.json for each example.
#
# With --espeak (only needed if you build a neutts-NANO app):
#   4. Fetches the espeak-ng data the nano phonemizer needs. The
#      multilingual TTS model and all shipped examples do NOT need this.
#
# Usage:
#   ./scripts/setup.sh            # AAR symlinks + secrets
#   QAIRT=~/Qualcomm/AIStack/QAIRT/2.42.0.251225 ./scripts/setup.sh
#   ./scripts/setup.sh --espeak   # also fetch espeak-ng data for nano apps
#
# Optional env:
#   QAIRT  Path to your Qualcomm AI Runtime (QAIRT) SDK 2.42 install
#          (e.g. ~/Qualcomm/AIStack/QAIRT/2.42.0.251225). When set, the
#          four Genie backend libs (the GenAiTransformer trio +
#          libQnnCpu.so) are copied from
#          $QAIRT/lib/aarch64-android/ into the plugin's jniLibs so
#          consumer apps inherit them via AGP merge. These libs are NOT
#          on Maven and are NOT redistributed by this SDK. Without them
#          any Genie pipeline crashes at first use with
#          `dlopen failed: library "libQnnGenAiTransformer.so" not found`.
#          QAIRT 2.42.0 is required — the shipped libStagenie.so is
#          coupled to that runtime.
#
# Safe to re-run; every step short-circuits if its output already exists.

set -euo pipefail

WANT_ESPEAK=0
for arg in "$@"; do
    case "$arg" in
        --espeak) WANT_ESPEAK=1 ;;
        -h|--help)
            sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugin/thestage_android_sdk"
PLUGIN_LIBS="$PLUGIN_DIR/android/libs"
PLUGIN_JNI="$PLUGIN_DIR/android/src/main/jniLibs/arm64-v8a"

err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
ok()   { printf '[ok] %s\n' "$*"; }

# ---------------------------------------------------------------
# 1. Symlink the prebuilt AARs into the plugin's android/libs/
# ---------------------------------------------------------------
# The plugin declares them compileOnly and the example apps
# implementation() them from this single directory. The AARs
# themselves live at the repo root.
AARS=(
    TheStageCore.aar
    onnxruntime-android.aar
)
mkdir -p "$PLUGIN_LIBS"
for aar in "${AARS[@]}"; do
    [ -f "$REPO_ROOT/$aar" ] || err "missing prebuilt AAR: $aar"
    link="$PLUGIN_LIBS/$aar"
    if [ -e "$link" ] || [ -L "$link" ]; then
        ok "$aar symlink already present"
    else
        # From plugin/thestage_android_sdk/android/libs/ up four
        # levels lands at the repo root, where the AARs live.
        ln -s "../../../../$aar" "$link"
        ok "linked $aar"
    fi
done

# ---------------------------------------------------------------
# 2. Copy the four Genie/QNN QAIRT runtime libs into jniLibs
# ---------------------------------------------------------------
# The Genie backend dlopens the GenAiTransformer trio + libQnnCpu.so
# at runtime. They are NOT on the qnn-runtime Maven artifact and NOT
# redistributed here, so we copy them from a local QAIRT 2.42 install
# when $QAIRT is set. Consumer apps inherit them via AGP jniLibs
# merge. QAIRT 2.42.0 is required — the shipped libStagenie.so is
# coupled to that runtime.
#
# NOTE: the Genie generation runtime itself is NOT copied here — it
# ships as libStagenie.so inside TheStageCore.aar (our patched Genie
# build). Stock libGenie.so from QAIRT is neither loaded nor needed.
QAIRT_LIBS=(
    libQnnGenAiTransformer.so
    libQnnGenAiTransformerCpuOpPkg.so
    libQnnGenAiTransformerModel.so
    libQnnCpu.so
)

__have_all_qairt_libs() {
    for lib in "${QAIRT_LIBS[@]}"; do
        [ -f "$PLUGIN_JNI/$lib" ] || return 1
    done
    return 0
}

if [ -n "${QAIRT:-}" ]; then
    QAIRT_SRC="$QAIRT/lib/aarch64-android"
    [ -d "$QAIRT_SRC" ] || err "\$QAIRT/lib/aarch64-android not found ($QAIRT)"
    mkdir -p "$PLUGIN_JNI"
    for lib in "${QAIRT_LIBS[@]}"; do
        src="$QAIRT_SRC/$lib"
        dst="$PLUGIN_JNI/$lib"
        [ -f "$src" ] || err "$lib not found at $src"
        cp "$src" "$dst"
        ok "copied $lib into plugin jniLibs/arm64-v8a/"
    done
elif __have_all_qairt_libs; then
    ok "Genie/QNN QAIRT libs already present in plugin jniLibs/"
else
    info "QAIRT env not set — skipping Genie/QNN lib copy."
    info "The Snapdragon NPU (qnn-runtime Maven) path still works, but"
    info "any Genie pipeline (on-device LLM, NeuTTS Genie) crashes at"
    info "first use with 'dlopen failed: library"
    info "\"libQnnGenAiTransformer.so\" not found'. Re-run with:"
    info "  QAIRT=~/Qualcomm/AIStack/QAIRT/2.42.0.251225 ./scripts/setup.sh"
fi

# ---------------------------------------------------------------
# 3. Bootstrap per-example secrets.json from secrets.example.json
# ---------------------------------------------------------------
for app_dir in "$REPO_ROOT"/examples/*/ ; do
    [ -d "$app_dir" ] || continue
    template="$app_dir/secrets.example.json"
    target="$app_dir/secrets.json"
    if [ -f "$template" ] && [ ! -f "$target" ]; then
        cp "$template" "$target"
        info "Created $target — fill in your keys before running."
    fi
done

# ---------------------------------------------------------------
# 4. (opt-in) espeak-ng data for neutts-nano apps
# ---------------------------------------------------------------
if [ "$WANT_ESPEAK" -eq 1 ]; then
    info "espeak-ng data is only required for neutts-nano apps."
    info "The multilingual TTS model and all shipped examples do NOT"
    info "need it. See plugin/thestage_android_sdk/README.md for the"
    info "phonemizer wiring if you are building a nano app."
fi

# ---------------------------------------------------------------
# 5. Verify
# ---------------------------------------------------------------
errors=0
for aar in "${AARS[@]}"; do
    [ -f "$PLUGIN_LIBS/$aar" ] || { echo "AAR symlink broken: $aar"; errors=1; }
done

if [ $errors -ne 0 ]; then
    err "Setup completed with errors. See messages above."
fi

cat <<'EOF'

Setup complete.

Next steps:
  1. Edit examples/<app>/secrets.json and put in your TheStage API token
     (and OpenAI key for voice_agent).
  2. Build and run on a connected Snapdragon device:
       cd examples/tts_front_stream
       flutter pub get
       flutter run --release \
           --dart-define-from-file=secrets.json \
           -d <YOUR_DEVICE_ID>

Use `flutter devices` to find the device id.
EOF
