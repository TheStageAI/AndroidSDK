#!/usr/bin/env bash
#
# One-time host setup for the TheStage Android SDK distribution.
#
# What it does (by default):
#   1. Symlinks the two prebuilt AARs (TheStageCore + the ONNX
#      Runtime AAR) into the Flutter plugin's android/libs/, so both
#      the plugin and the example apps resolve them from one place.
#   2. Copies the Genie/QNN QAIRT runtime libs into the plugin's
#      jniLibs/arm64-v8a/ (only when $QAIRT is set — see below).
#   3. Bootstraps secrets.json from secrets.example.json for each example.
#
# Usage:
#   ./scripts/setup.sh            # AAR symlinks + secrets
#   QAIRT=~/Qualcomm/AIStack/QAIRT/2.51.0.260929 ./scripts/setup.sh
#
# Optional env:
#   QAIRT  Path to your Qualcomm AI Runtime (QAIRT) SDK 2.51 install
#          (e.g. ~/Qualcomm/AIStack/QAIRT/2.51.0.260929). When set, the
#          Genie backend libs are copied from
#          $QAIRT/lib/aarch64-android/ into the plugin's jniLibs so
#          consumer apps inherit them via AGP merge. These libs are NOT
#          on Maven and are NOT redistributed by this SDK. Every
#          published model runs without them; only a bundle that asks
#          for the GenAiTransformer Genie backend needs them.
#          QAIRT 2.51.0 is required — the shipped libStagenie.so is
#          coupled to that runtime.
#
# Safe to re-run; every step short-circuits if its output already exists.

set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
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
# 2. Copy the Genie/QNN QAIRT runtime libs into jniLibs
# ---------------------------------------------------------------
# The Genie backend dlopens the GenAiTransformer libs + libQnnCpu.so
# at runtime. They are NOT on the qnn-runtime Maven artifact and NOT
# redistributed here, so we copy them from a local QAIRT 2.51 install
# when $QAIRT is set. Consumer apps inherit them via AGP jniLibs
# merge. QAIRT 2.51.0 is required — the shipped libStagenie.so is
# coupled to that runtime.
#
# NOTE: the Genie generation runtime itself is NOT copied here — it
# ships as libStagenie.so inside TheStageCore.aar (our patched Genie
# build). Stock libGenie.so from QAIRT is neither loaded nor needed.
# Required: present in every supported QAIRT.
QAIRT_LIBS=(
    libQnnGenAiTransformer.so
    libQnnGenAiTransformerModel.so
    libQnnCpu.so
    # HTP performance settings for Genie bundles (NeuTTS).
    libQnnHtpNetRunExtensions.so
)

# Present in QAIRT 2.42/2.45 but NOT shipped in 2.51 — Qualcomm
# dropped it. Copied when the install has it, skipped otherwise, so
# the pinned 2.51 install is not treated as broken.
QAIRT_LIBS_OPTIONAL=(
    libQnnGenAiTransformerCpuOpPkg.so
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
    for lib in "${QAIRT_LIBS_OPTIONAL[@]}"; do
        src="$QAIRT_SRC/$lib"
        if [ -f "$src" ]; then
            cp "$src" "$PLUGIN_JNI/$lib"
            ok "copied $lib into plugin jniLibs/arm64-v8a/"
        else
            info "$lib absent from this QAIRT (expected on 2.51) - skipping"
        fi
    done
elif __have_all_qairt_libs; then
    ok "Genie/QNN QAIRT libs already present in plugin jniLibs/"
else
    info "QAIRT env not set — skipping the optional QAIRT lib copy."
    info "Every published model runs with the qnn-runtime Maven"
    info "artifact alone. Only a bundle that asks for the"
    info "GenAiTransformer Genie backend needs these libs; for one,"
    info "re-run with QAIRT=<QAIRT 2.51.0 install> ./scripts/setup.sh"
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
# 4. Verify
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
       cd examples/tutor_tts
       flutter pub get
       flutter run --release \
           --dart-define-from-file=secrets.json \
           -d <YOUR_DEVICE_ID>

Use `flutter devices` to find the device id.
EOF
