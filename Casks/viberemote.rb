cask "viberemote" do
  version "0.1.7"
  sha256 "54f0717ec38ca5f154361e771715f4d08f1685b472b0da7339b8e46293d4c9e2"

  url "https://github.com/whitesticker/viberemote/releases/download/v#{version}/VibeRemote-#{version}.zip"
  name "VibeRemote"
  desc "Control your Mac with a DualSense or Apple TV remote"
  homepage "https://github.com/whitesticker/viberemote"

  depends_on macos: :sonoma

  app "VibeRemote.app"

  zap trash: [
    "~/Library/Preferences/com.iremote.app.plist",
  ]

  caveats <<~EOS
    Enable VibeRemote in System Settings → Privacy & Security → Accessibility.
    This build is ad-hoc signed; first launch may require Right-click → Open.
  EOS
end
