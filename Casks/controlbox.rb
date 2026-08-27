cask "controlbox" do
  version "0.1.10"
  sha256 "59b3a7ebd3a65f70d195f2eee653cfc32d422a222af6da757c3f1530d2046bc4"

  url "https://github.com/whitesticker/controlbox/releases/download/v#{version}/ControlBox-#{version}.zip"
  name "Control Box"
  desc "Control your Mac with a DualSense or Apple TV remote"
  homepage "https://github.com/whitesticker/controlbox"

  depends_on macos: :sonoma

  app "ControlBox.app"

  zap trash: [
    "~/Library/Preferences/com.whitesticker.controlbox.plist",
    "~/Library/Preferences/com.iremote.app.plist",
  ]

  caveats <<~EOS
    Enable Control Box in System Settings → Privacy & Security → Accessibility.
    This build is ad-hoc signed; first launch may require Right-click → Open.
  EOS
end
