cask "controlbox" do
  version "0.1.38"
  sha256 "6b6dff9e4b2e1130c18448f4b10e69522301019ba7e610a14449ef42ea56138e"

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
