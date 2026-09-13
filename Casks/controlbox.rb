cask "controlbox" do
  version "0.1.48"
  sha256 "8b3d5320b4b583884ad54ba4af0ae7c7908087e10a1d718e911190c8cc54baf0"

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
