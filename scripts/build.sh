#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# Keep compiler caches inside the project so builds work in restricted environments.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
# Accessibility permission is tied to the signature. With an ad-hoc signature, macOS forgets the
# permission after every rebuild, so sign with the stable self-signed "MacSnip Release" certificate,
# shared with MacSnip, when it is in the keychain. Set SIGN_IDENTITY to use another certificate, or
# "-" to force ad-hoc signing.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  if security find-certificate -c "MacSnip Release" >/dev/null 2>&1; then
    identity="MacSnip Release"
  else
    identity="-"
  fi
fi
architectures=()
if [[ "${1:-}" == "--universal" ]]; then
  architectures=(--arch arm64 --arch x86_64)
fi
swift build -c release --disable-sandbox -debug-info-format none "${architectures[@]}"
bin_path=$(swift build -c release --disable-sandbox -debug-info-format none "${architectures[@]}" --show-bin-path)
app="$PWD/dist.noindex/MacMouse.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# Replace the executable instead of overwriting a binary that may be running.
cp "$bin_path/MacMouse" "$app/Contents/MacOS/MacMouse.new"
mv -f "$app/Contents/MacOS/MacMouse.new" "$app/Contents/MacOS/MacMouse"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/dist.noindex"
cp "$PWD/dist.noindex/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
# The hardened runtime enables library validation and ignores DYLD_* variables, so another process
# cannot inject code into an app that holds Accessibility access. It works with any signature.
codesign --force --options runtime --sign "$identity" --identifier io.macmouse.app "$app"
rm -f "$PWD/dist.noindex/MacMouse.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$PWD/dist.noindex/MacMouse.zip"
echo "Built: $app"
echo "Install: cp -R dist.noindex/MacMouse.app /Applications/ && open /Applications/MacMouse.app"
