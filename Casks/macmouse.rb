cask "macmouse" do
  version "1.0.1"
  sha256 "74dc99d5c0ce7078a793bfb9fa2cc471cb1a0cb972d0e37a7b5fd77a08f18f32"

  url "https://github.com/henrikhestnes/MacMouse/releases/download/v#{version}/MacMouse.zip"
  name "MacMouse"
  desc "Pointer speed, scroll wheel and mouse button settings for mice"
  homepage "https://github.com/henrikhestnes/MacMouse"

  depends_on macos: :sonoma

  app "MacMouse.app"

  uninstall quit: "io.macmouse.app"

  zap trash: "~/Library/Preferences/io.macmouse.app.plist"

  caveats <<~EOS
    This build is signed with a self-signed certificate and has not been notarized by Apple.

    MacMouse needs Accessibility access. Enable it in
    System Settings → Privacy & Security → Accessibility. Upgrades keep the permission.
  EOS
end
