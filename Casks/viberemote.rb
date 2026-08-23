cask "viberemote" do
  version "0.1.6"
  sha256 "192c45b9c68544b4ae7929be068fccffc8940b0715382e32425a5a32ad2e7f41"

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
