cask "controlbox" do
  version "0.1.39"
  sha256 "f0b19b18d712fb1aa559c578dcac023fa84be2b4062aa2e17db0e2f4764d787f"

  url "https://github.com/whitesticker/controlbox/releases/download/v#{version}/ControlBox-#{version}.zip"
  name "Control Box"
  desc "Control your Mac with a DualSense, Siri Remote, MX Master, or MX Mechanical"
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
