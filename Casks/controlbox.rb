cask "controlbox" do
  version "0.1.16"
  sha256 "28565d1c390527b1dc8a588f71e508757c27fa3f7d212fcd9e9a6ae15bb950cd"

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
