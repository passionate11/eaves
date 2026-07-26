#!/bin/bash
# Builds DeskNote.app with Command Line Tools only — no Xcode, no project file.
#
#   ./build.sh            fast debug build, native arch only
#   ./build.sh release    optimised universal binary (arm64 + x86_64)
#
# The debug path stays single-arch on purpose: -O -wmo across two slices takes
# minutes, and nothing about day-to-day editing needs an Intel slice.
set -euo pipefail

cd "$(dirname "$0")"
APP="DeskNote.app"
BIN="$APP/Contents/MacOS/DeskNote"
DEPLOY_TARGET=13.0

source Tools/vfs-overlay.sh

if [ "${1:-}" = "release" ]; then
  SWIFT_OPT=(-O -whole-module-optimization)
  # Universal, so the app runs on Intel Macs too. Without this the binary is
  # arm64-only and simply refuses to launch on anything pre-Apple-Silicon.
  ARCHS=(arm64 x86_64)
else
  SWIFT_OPT=(-Onone)
  ARCHS=("$(uname -m)")
fi

# The icon is a compiled drawing (Tools/make-icon.swift), rebuilt only when its
# source is newer than the .icns — it changes far less often than the app does.
if [ ! -f Resources/AppIcon.icns ] || [ Tools/make-icon.swift -nt Resources/AppIcon.icns ]; then
  ./Tools/make-icon.sh
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>DeskNote</string>
  <key>CFBundleDisplayName</key>       <string>DeskNote</string>
  <key>CFBundleExecutable</key>        <string>DeskNote</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>CFBundleIdentifier</key>        <string>com.hpc.desknote</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key>           <string>1</string>
  <key>LSMinimumSystemVersion</key>    <string>${DEPLOY_TARGET}</string>
  <key>LSUIElement</key>               <true/>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>NSPrincipalClass</key>          <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>  <string>MIT License</string>
</dict>
</plist>
PLIST

mkdir -p .build/slices
SLICES=()
for arch in "${ARCHS[@]}"; do
  out=".build/slices/DeskNote-$arch"
  swiftc "${SWIFT_OPT[@]}" \
    "${VFS_ARGS[@]}" \
    -target "${arch}-apple-macosx${DEPLOY_TARGET}" \
    -framework AppKit -framework ServiceManagement \
    Sources/*.swift -o "$out"
  SLICES+=("$out")
done

if [ "${#SLICES[@]}" -gt 1 ]; then
  lipo -create "${SLICES[@]}" -output "$BIN"
else
  cp "${SLICES[0]}" "$BIN"
fi

# Ad-hoc signature. Enough for the app to run on the machine that built it,
# which is what building from source means. Distributing a prebuilt .app to
# other people needs a Developer ID certificate and notarization instead —
# see docs/DISTRIBUTION.md.
codesign --force --sign - --identifier com.hpc.desknote "$APP"

echo "built: $(pwd)/$APP  [$(lipo -archs "$BIN")]"
