cask "controlbox" do
  version "0.1.44"
  sha256 "da373d33d05a111a47dd740ea163eca1d1a910ad581de8ed56f4ae2d4e0f2f4f"

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
