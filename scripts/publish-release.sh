#!/bin/zsh
# Build, sign and publish a UForge release to the fork's GitHub Releases.
# Installed copies pick it up through the signed appcast on their next hourly
# check and install it automatically.
#   scripts/publish-release.sh 0.8.1 45
# Requires: gh (authenticated), the Sparkle key in the login Keychain
# (account com.unqsoft.uforge), and a clean, pushed working tree.
set -euo pipefail
cd "${0:A:h:h}"
if (( $# != 2 )); then print -u2 'Usage: scripts/publish-release.sh VERSION BUILD'; exit 1; fi
version=$1 build=$2 tag="v$1-$2"
repository=$(plutil -extract PublicRepository raw -o - Configuration/Updates.public.plist)
command -v gh >/dev/null || { print -u2 'Install the GitHub CLI first: brew install gh && gh auth login'; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then print -u2 'Commit your changes before publishing a release.'; exit 1; fi
git push fork HEAD
# Every release must have a higher build number than the one users already have.
if gh release view --repo "$repository" >/dev/null 2>&1; then
  previous="$PWD/build/previous-appcast.xml"
  gh release download --repo "$repository" --pattern appcast.xml --output "$previous" --clobber
  python3 scripts/validate-update-feed.py "$previous" "$build" --must-be-newer
fi
scripts/prepare-public-release.sh "$version" "$build"
app="$PWD/build/public-$version-$build/UForge.app"
upload="$PWD/build/public-upload-$version-$build"
dmg="$upload/UForge-$version.dmg"
staging=$(mktemp -d)
ditto "$app" "$staging/UForge.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "UForge $version" -srcfolder "$staging" -format UDZO -ov "$dmg" >/dev/null
rm -rf "$staging"
gh release create "$tag" --repo "$repository" --target "$(git rev-parse HEAD)" --title "UForge $version ($build)" \
  --notes "UForge $version (build $build)" --latest "$upload"/*
print "Published $tag to https://github.com/$repository/releases/tag/$tag"
