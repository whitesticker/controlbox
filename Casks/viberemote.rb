cask "viberemote" do
  version "0.1.10"
  sha256 "59b3a7ebd3a65f70d195f2eee653cfc32d422a222af6da757c3f1530d2046bc4"

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
