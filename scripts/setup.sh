#!/usr/bin/env bash
#
# One-time host setup for the TheStage Android SDK distribution.
#
# What it does:
#   1. Symlinks the prebuilt TheStageCore.aar into the Flutter
#      plugin's android/libs/, so both the plugin and the example apps
#      resolve it from one place. (ONNX Runtime comes from Maven
#      Central; the example apps declare it.)
#   2. Bootstraps secrets.json from secrets.example.json for each example.
#
# Usage:
#   ./scripts/setup.sh
#
# Safe to re-run; every step short-circuits if its output already exists.

set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugin/thestage_android_sdk"
PLUGIN_LIBS="$PLUGIN_DIR/android/libs"

err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
ok()   { printf '[ok] %s\n' "$*"; }

# ---------------------------------------------------------------
# 1. Symlink the prebuilt AAR into the plugin's android/libs/
# ---------------------------------------------------------------
# The plugin declares it compileOnly and the example apps
# implementation() it from this single directory. The AAR
# itself lives at the repo root.
AARS=(
    TheStageCore.aar
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
# 2. Bootstrap per-example secrets.json from secrets.example.json
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
# 3. Verify
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
