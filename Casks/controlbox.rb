cask "controlbox" do
  version "0.1.18"
  sha256 "22842b500c30ec26b47b8e36aca7b1fb1196cd2c8de0954044c23e72696b4588"

  url "https://github.com/whitesticker/controlbox/releases/download/v#{version}/ControlBox-#{version}.zip"
  name "Control Box"
  desc "Control your Mac with a DualSense, Siri Remote, or MX Master"
  homepage "https://github.com/whitesticker/controlbox"

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
