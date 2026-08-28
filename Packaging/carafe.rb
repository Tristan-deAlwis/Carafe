# Homebrew cask for Carafe.
#
# This file is a TEMPLATE. It belongs in a separate tap repository — Homebrew
# requires the repo be named `homebrew-<tap>` — not in this one:
#
#   1. Create github.com/Tristan-deAlwis/homebrew-carafe
#   2. Copy this file to Casks/carafe.rb there
#   3. Update `version` and `sha256` from the release (Scripts/release.sh prints both)
#
# Users then install with:
#
#   brew tap tristan-dealwis/carafe
#   brew install --cask carafe
#
# Submitting to the main homebrew/cask tap requires meeting its notability
# thresholds, which a new repository will not; move it there once the project has
# traction.
cask "carafe" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/Tristan-deAlwis/Carafe/releases/download/v#{version}/Carafe-#{version}.zip",
      verified: "github.com/Tristan-deAlwis/Carafe/"
  name "Carafe"
  desc "Menu bar reminder to drink water through the day"
  homepage "https://github.com/Tristan-deAlwis/Carafe"

  # Carafe targets macOS 14. Universal binary, so no arch constraint.
  depends_on macos: ">= :sonoma"

  app "Carafe.app"

  # Until releases are notarized, Gatekeeper refuses to open the app and reports
  # it as "damaged". Remove this stanza — and the caveat below — once a Developer
  # ID signature is in place, because suppressing quarantine is a real reduction
  # in the protection Homebrew normally gives users.
  #
  # Delete the next line when releases are notarized:
  # rubocop:disable Style/RedundantParentheses
  no_quarantine
  # rubocop:enable Style/RedundantParentheses

  uninstall quit: "com.tristandealwis.carafe",
            login_item: "Carafe"

  zap trash: [
    "~/Library/Application Support/Carafe",
    "~/Library/Preferences/com.tristandealwis.carafe.plist",
    "~/Library/Caches/com.tristandealwis.carafe",
  ]

  caveats <<~EOS
    Carafe lives in the menu bar and has no Dock icon. Click the carafe outline
    in the menu bar to open it.

    This build is not notarized by Apple. If macOS reports that Carafe is
    "damaged", it is not — clear the quarantine flag:

      xattr -d com.apple.quarantine /Applications/Carafe.app

    macOS also declines to deliver notifications from unsigned apps. Carafe
    detects this and marks its menu bar icon when a reminder is due instead.
  EOS
end
