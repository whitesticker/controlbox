cask "viberemote" do
  version "0.1.1"
  sha256 "d90ea234792465edfca6e16614b500db25bd4e9baf1fb26236d18f2aba959a2e"

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
