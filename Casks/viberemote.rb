cask "viberemote" do
  version "0.1.9"
  sha256 "f24a7a93a019216c87d82c4eed9ba2c5db93f60c02ea0ea5c73fe6fb2d451c7d"

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
