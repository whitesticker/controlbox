cask "controlbox" do
  version "0.1.20"
  sha256 "2e34887d0c6c8e19a8ffe8fb46f723c7178e88599d60b80152cc81d45de615ca"

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
