#!/bin/zsh
# Builds "Aries Dynamic Island.app".
#   ./build.sh            build into ./build
#   ./build.sh --install  build, copy to /Applications and launch
#   ./build.sh --zip      build and make a zip for a GitHub release
set -e
cd "$(dirname "$0")"
swift build -c release
NAME="Aries Dynamic Island"
APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Aries "$APP/Contents/MacOS/Aries"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f build/AppIcon.icns ] || [ Resources/Branding/AriesLogo.png -nt build/AppIcon.icns ] || [ scripts/make_icon.swift -nt build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make_icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Branding/*.png "$APP/Contents/Resources/"
# Ad-hoc signature with a stable designated requirement (the bundle ID), so macOS keeps
# permissions (Automation, Accessibility, Calendars…) across updates instead of re-asking.
codesign --force --deep --sign - -r='designated => identifier "app.aries.dynamicisland"' "$APP"
echo "Built $APP"
if [ "$1" = "--zip" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  (cd build && ditto -c -k --keepParent "$NAME.app" "Aries-Dynamic-Island-$VERSION.zip")
  echo "Created build/Aries-Dynamic-Island-$VERSION.zip"
fi
if [ "$1" = "--install" ]; then
  pkill -x Aries 2>/dev/null || true
  pkill -x Isle 2>/dev/null || true        # older name of this app
  rm -rf /Applications/Isle.app "/Applications/$NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$NAME.app"
  echo "Installed to /Applications/$NAME.app"
fi
