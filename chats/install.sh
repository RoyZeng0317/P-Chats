#!/usr/bin/env bash
# P Chats — One-line setup for macOS / Linux
# Usage: bash install.sh [--run | --build-android | --build-apk]
set -euo pipefail

FIREBASE_PROJECT="p-chats-26652"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

log()  { echo -e "${GREEN}✔ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠ $*${NC}"; }
die()  { echo -e "${RED}✘ $*${NC}"; exit 1; }

echo ""
echo "╔══════════════════════════════╗"
echo "║        P Chats Setup         ║"
echo "╚══════════════════════════════╝"
echo ""

# ── 1. Check Flutter ──────────────────────────────────────────────────────────
if ! command -v flutter &>/dev/null; then
    die "Flutter SDK not found.\nInstall from: https://flutter.dev/docs/get-started/install"
fi
FLUTTER_VERSION=$(flutter --version 2>&1 | head -1)
log "Flutter: $FLUTTER_VERSION"

# ── 2. Check Firebase CLI ─────────────────────────────────────────────────────
if ! command -v firebase &>/dev/null; then
    warn "Firebase CLI not found — installing via npm..."
    if ! command -v npm &>/dev/null; then
        die "npm not found. Install Node.js first: https://nodejs.org"
    fi
    npm install -g firebase-tools
fi
log "Firebase CLI: $(firebase --version 2>&1 | head -1)"

# ── 3. Flutter pub get ────────────────────────────────────────────────────────
log "Installing Flutter packages..."
flutter pub get

# ── 3b. Generate app icons ────────────────────────────────────────────────────
log "Generating app icons..."
dart run flutter_launcher_icons || warn "Icon generation failed (non-fatal)"

# ── 4. Firebase login (if not already logged in) ─────────────────────────────
if ! firebase login:list 2>&1 | grep -q "@"; then
    warn "Not logged in to Firebase — opening browser..."
    firebase login
fi

# ── 5. Deploy Firestore rules ─────────────────────────────────────────────────
log "Deploying Firestore security rules..."
firebase deploy --only firestore:rules --project "$FIREBASE_PROJECT"

echo ""
echo -e "${GREEN}══════════════════════════════"
echo -e "  ✅  Setup complete!"
echo -e "══════════════════════════════${NC}"
echo ""

# ── 6. Optional: run / build ──────────────────────────────────────────────────
ARG="${1:-}"
case "$ARG" in
  --run)
    log "Starting app..."
    flutter run
    ;;
  --build-android | --build-apk)
    log "Building Android release APK..."
    flutter build apk --release
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    log "APK → $APK_PATH"
    ;;
  --build-linux)
    log "Building Linux release..."
    flutter build linux --release
    log "Binary → build/linux/x64/release/bundle/"
    ;;
  *)
    echo "Run the app with:"
    echo "  flutter run"
    echo ""
    echo "Or rebuild:"
    echo "  bash install.sh --build-android"
    echo "  bash install.sh --build-linux"
    ;;
esac
