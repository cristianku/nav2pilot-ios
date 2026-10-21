#!/usr/bin/env bash
# Builds Nav2Pilot for iOS on this Mac and uploads it to TestFlight. Nothing runs on GitHub.
#
#   scripts/build-release.sh           tests + simulator build, then archive and upload to TestFlight
#   scripts/build-release.sh 1.1.0     same, with version 1.1.0 instead of the last version with patch + 1
#   scripts/build-release.sh --local   only the tests and the simulator build, nothing goes to TestFlight
#
# Version and build number come from the Nav2Pilot archives in Xcode's Archives folder: build = highest + 1.
# Signing is automatic with the Xcode account (team TG24AHP9SF).
# pipefail: a failed test run or build stops the script, even though its output goes through grep
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

TEAM_ID="TG24AHP9SF"
BRANCH="main"
ARCHIVES_DIR="$HOME/Library/Developer/Xcode/Archives"

LOCAL_ONLY="no"
VERSION_ARG=""
if [ "${1:-}" = "--local" ]; then
  LOCAL_ONLY="yes"
elif [ -n "${1:-}" ]; then
  VERSION_ARG="$1"
fi

if [ "$LOCAL_ONLY" = "no" ]; then
  echo "== what will be built"
  CURRENT_BRANCH="$(git branch --show-current)"
  if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
    echo "You are on '$CURRENT_BRANCH', but TestFlight is built from '$BRANCH'."
    exit 1
  fi
  if [ -n "$(git status --porcelain)" ]; then
    echo "Uncommitted changes: commit them first, TestFlight builds only committed code."
    git status --short
    exit 1
  fi
  echo "$BRANCH at $(git log -1 --format='%h %s')"
fi

echo "== xcodegen"
xcodegen generate --quiet
if [ "$LOCAL_ONLY" = "no" ] && [ -n "$(git status --porcelain)" ]; then
  echo "xcodegen changed the project: commit it first."
  git status --short
  exit 1
fi

echo "== package tests"
swift test --package-path Nav2PilotKit 2>&1 | grep -E "Executed [0-9]+ tests|error:|failed" | tail -1

echo "== app build for the simulator"
xcodebuild -project Nav2Pilot.xcodeproj -scheme Nav2Pilot \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

if [ "$LOCAL_ONLY" = "yes" ]; then
  echo "Local checks done (--local: nothing sent to TestFlight)."
  exit 0
fi

echo "== version and build"
# the archive with the highest build number is the last one uploaded
LAST_VERSION=""
LAST_BUILD="0"
for ARCHIVE_PATH in "$ARCHIVES_DIR"/*/"Nav2Pilot "*.xcarchive; do
  if [ ! -f "$ARCHIVE_PATH/Info.plist" ]; then
    continue
  fi
  ARCHIVE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE_PATH/Info.plist")"
  ARCHIVE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE_PATH/Info.plist")"
  if [ "$ARCHIVE_BUILD" -gt "$LAST_BUILD" ]; then
    LAST_BUILD="$ARCHIVE_BUILD"
    LAST_VERSION="$ARCHIVE_VERSION"
  fi
done
if [ -z "$LAST_VERSION" ]; then
  echo "No Nav2Pilot archive in $ARCHIVES_DIR: cannot tell the last version and build."
  exit 1
fi
BUILD="$((LAST_BUILD + 1))"
if [ -n "$VERSION_ARG" ]; then
  VERSION="$VERSION_ARG"
else
  IFS=. read -r MAJOR MINOR PATCH <<< "$LAST_VERSION"
  VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
fi
echo "last uploaded: $LAST_VERSION ($LAST_BUILD), new: $VERSION ($BUILD)"

echo "== archive"
# straight into Xcode's Archives folder, so it shows in the Organizer and the next run finds it
ARCHIVE="$ARCHIVES_DIR/$(date +%Y-%m-%d)/Nav2Pilot $VERSION ($BUILD).xcarchive"
xcodebuild -project Nav2Pilot.xcodeproj -scheme Nav2Pilot -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  archive 2>&1 | grep -E "error:|ARCHIVE (SUCCEEDED|FAILED)"

echo "== export and upload to TestFlight"
# system PATH: the export runs /usr/bin/rsync, which starts the first rsync in PATH as its other end, and
# Homebrew's rsync rejects --extended-attributes ("Copy failed")
rm -rf build/export
PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates 2>&1 | grep -E "error:|Upload succeeded|EXPORT (SUCCEEDED|FAILED)"

echo
echo "Uploaded $VERSION ($BUILD). TestFlight shows it after Apple's processing (usually 5-15 minutes)."
