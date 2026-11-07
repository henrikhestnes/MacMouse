cask "macmouse" do
  version "1.0.0"
  sha256 "8526ec5fe2921791fb1e953d5cbc1ba70193c324cade80de5a20429c7b8e1ab5"

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
