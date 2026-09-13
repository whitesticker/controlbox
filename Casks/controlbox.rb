cask "controlbox" do
  version "0.1.49"
  sha256 "18a3b25642621ee79b9a8e323c2948148827e883208a6b59f308e76c39baa6e9"

  url "https://github.com/whitesticker/controlbox/releases/download/v#{version}/ControlBox-#{version}.zip"
  name "Control Box"
  desc "Control your Mac with a DualSense, Xbox or other gamepad, Siri Remote, MX Master, or MX Mechanical"
  homepage "https://whitesticker.github.io/controlbox/"

  depends_on macos: :sonoma

  app "ControlBox.app"

  zap trash: [
    "~/Library/Preferences/com.whitesticker.controlbox.plist",
    "~/Library/Preferences/com.iremote.app.plist",
  ]

  caveats <<~EOS
    Enable Control Box in System Settings → Privacy & Security → Accessibility.
    First launch may require Right-click → Open.
  EOS
end
