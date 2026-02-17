#!/bin/bash
set -euo pipefail

# Full E2E build + test pipeline for WDK on JSC
#
# Builds BareKit (iOS + macOS), generates bundles, runs swift tests,
# assembles the starter app, and launches on simulator.
#
# Assumes sibling directory layout:
#   parent/
#     bare-kit-jsc/      (ohwhen/bare-kit#jsc)
#     wdk-swift-core/    (ohwhen/wdk-swift-core#jsc)
#     wdk-starter-jsc/   (ohwhen/wdk-starter-swift#jsc)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STARTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$STARTER_DIR/.." && pwd)"
BARE_KIT_DIR="$ROOT_DIR/bare-kit-jsc"
WDK_CORE_DIR="$ROOT_DIR/wdk-swift-core"
SIMULATOR="iPhone 16 Pro"

for dir in "$BARE_KIT_DIR" "$WDK_CORE_DIR" "$STARTER_DIR"; do
  if [ ! -d "$dir" ]; then
    echo "ERROR: Missing directory: $dir"
    echo "Expected: bare-kit-jsc/ wdk-swift-core/ wdk-starter-jsc/ as siblings"
    exit 1
  fi
done

step() { echo ""; echo "==> $1"; }
TOTAL_START=$SECONDS

generate_and_build() {
  local build_dir=$1
  local label=$2
  shift 2

  cd "$BARE_KIT_DIR"
  rm -rf "$build_dir"

  echo "  Generating $label..."
  bare-make generate "$@" --build "$build_dir" \
    -D BARE_ENGINE=github:ohwhen/libjsc#jsc -D BARE_PREBUILDS=OFF > /dev/null 2>&1

  echo "  Building $label..."
  bare-make build --build "$build_dir" > /dev/null 2>&1
}

# ─── Step 1: Build BareKit (iOS + macOS) ──────────────────────────────────────

step "Step 1/6: Building BareKit"
STEP_START=$SECONDS

generate_and_build build/ios-arm64-jsc     "iOS device"    --platform ios --arch arm64
generate_and_build build/ios-sim-arm64-jsc "iOS simulator" --platform ios --simulator --arch arm64
generate_and_build build/macos-arm64-jsc   "macOS"         --platform darwin --arch arm64

echo "  Creating xcframework..."
rm -rf "$BARE_KIT_DIR/prebuilds/ios/BareKit.xcframework"
xcodebuild -create-xcframework \
  -framework "$BARE_KIT_DIR/build/ios-arm64-jsc/apple/BareKit.framework" \
  -framework "$BARE_KIT_DIR/build/ios-sim-arm64-jsc/apple/BareKit.framework" \
  -output "$BARE_KIT_DIR/prebuilds/ios/BareKit.xcframework" > /dev/null 2>&1

echo "  Done ($((SECONDS - STEP_START))s)"

# ─── Step 2: Generate WDK bundles (iOS + macOS) ──────────────────────────────

step "Step 2/6: Generating WDK bundles"
STEP_START=$SECONDS

cd "$WDK_CORE_DIR/WorkletSource/pear-wrk-wdk-jsonrpc"

if [ ! -d "node_modules" ]; then
  echo "  Installing npm dependencies..."
  npm install --silent 2>&1
fi

echo "  Building iOS bundle (bare-pack)..."
npm run build:bundle > /dev/null 2>&1

cd "$WDK_CORE_DIR"

echo "  Converting iOS bundle ESM → CJS..."
node Scripts/convert-bundle-esm-to-cjs.js \
  WorkletSource/pear-wrk-wdk-jsonrpc/generated/wdk-worklet.mobile.bundle --in-place

echo "  Generating macOS test bundle..."
bash Scripts/generate-macos-bundle.sh > /dev/null 2>&1

echo "  Done ($((SECONDS - STEP_START))s)"

# ─── Step 3: Swift tests (macOS) ─────────────────────────────────────────────

step "Step 3/6: Running swift tests"
STEP_START=$SECONDS

cd "$WDK_CORE_DIR"

mkdir -p Frameworks
cp -R "$BARE_KIT_DIR/build/macos-arm64-jsc/apple/BareKit.framework" Frameworks/

bash Scripts/test-with-frameworks.sh 2>&1

echo "  Done ($((SECONDS - STEP_START))s)"

# ─── Step 4: Assemble starter app ────────────────────────────────────────────

step "Step 4/6: Assembling starter app"
STEP_START=$SECONDS

cd "$STARTER_DIR"

rm -rf frameworks/BareKit.xcframework
cp -R "$BARE_KIT_DIR/prebuilds/ios/BareKit.xcframework" frameworks/
cp "$WDK_CORE_DIR/WorkletSource/pear-wrk-wdk-jsonrpc/generated/wdk-worklet.mobile.bundle" .
xcodegen generate > /dev/null 2>&1

echo "  Framework: $(du -sh frameworks/BareKit.xcframework | cut -f1)"
echo "  Bundle: $(du -sh wdk-worklet.mobile.bundle | cut -f1)"
echo "  Done ($((SECONDS - STEP_START))s)"

# ─── Step 5: Build starter app for simulator ─────────────────────────────────

step "Step 5/6: Building for iOS Simulator"
STEP_START=$SECONDS

cd "$STARTER_DIR"

# Find first matching simulator UDID
SIM_UDID=$(xcrun simctl list devices available -j 2>/dev/null \
  | python3 -c "
import sys, json
devs = json.load(sys.stdin)['devices']
for ds in devs.values():
    for d in ds:
        if '$SIMULATOR' in d['name'] and d['isAvailable']:
            print(d['udid'], end='')
            sys.exit(0)
" 2>/dev/null || true)

if [ -z "$SIM_UDID" ]; then
  echo "  WARNING: Could not auto-detect simulator. Using name match."
  DEST="platform=iOS Simulator,name=$SIMULATOR"
else
  DEST="id=$SIM_UDID"
fi

xcodebuild -project wdk-starter-swift.xcodeproj \
  -scheme wdk-starter-swift \
  -destination "$DEST" \
  -derivedDataPath build/DerivedData \
  clean build 2>&1 | tail -5

echo "  Done ($((SECONDS - STEP_START))s)"

# ─── Step 6: Install and run on simulator ─────────────────────────────────────

step "Step 6/6: Running on simulator"

cd "$STARTER_DIR"

APP_PATH=$(find build/DerivedData -name "wdk-starter-swift.app" -path "*/Debug-iphonesimulator/*" | head -1)
if [ -z "$APP_PATH" ]; then
  echo "  ERROR: Built app not found"
  exit 1
fi

SIM_TARGET="${SIM_UDID:-$SIMULATOR}"
xcrun simctl boot "$SIM_TARGET" 2>/dev/null || true
BUNDLE_ID="com.tether.wdk-starter-swift"
xcrun simctl install "$SIM_TARGET" "$APP_PATH"
xcrun simctl launch "$SIM_TARGET" "$BUNDLE_ID"

echo "  App launched on $SIMULATOR"
echo ""
echo "=== All steps complete ($((SECONDS - TOTAL_START))s total) ==="
echo "Tap 'Test WDK' in the app to verify end-to-end."
