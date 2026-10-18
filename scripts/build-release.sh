#!/usr/bin/env bash
# Checks Nav2Pilot for iOS locally, then has GitHub Actions build it and upload it to TestFlight.
#
#   scripts/build-release.sh           tests + simulator build here, then the TestFlight build on GitHub
#   scripts/build-release.sh --local   only the tests and the simulator build, nothing goes to TestFlight
#
# The TestFlight build is workflow "4. Build Nav2Pilot": it builds what is on GitHub (branch main), signs it
# with the Match certificates and uses the next TestFlight build number. So unpushed commits are not in it,
# and the script stops if there are any.
# pipefail: a failed test run or build stops the script, even though its output goes through grep
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

GITHUB_REPO="cristianku/nav2pilot-ios"
WORKFLOW="build_nav2pilot.yml"
BRANCH="main"

LOCAL_ONLY="no"
if [ "${1:-}" = "--local" ]; then
  LOCAL_ONLY="yes"
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

echo "== what GitHub will build"
git fetch --quiet origin "$BRANCH"
CURRENT_BRANCH="$(git branch --show-current)"
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
  echo "You are on '$CURRENT_BRANCH', but TestFlight is built from '$BRANCH'."
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Uncommitted changes (they would NOT be in the TestFlight build):"
  git status --short
  exit 1
fi
AHEAD="$(git rev-list --count "origin/$BRANCH..HEAD")"
if [ "$AHEAD" != "0" ]; then
  echo "$AHEAD commit(s) not pushed yet: run 'git push' first, the TestFlight build uses GitHub's $BRANCH."
  exit 1
fi
echo "$BRANCH at $(git log -1 --format='%h %s')"

echo "== TestFlight build on GitHub Actions"
gh workflow run "$WORKFLOW" -R "$GITHUB_REPO" --ref "$BRANCH"
# the new run takes a few seconds to show up in the list
sleep 8
RUN_ID="$(gh run list -R "$GITHUB_REPO" --workflow "$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId')"
echo "run: https://github.com/$GITHUB_REPO/actions/runs/$RUN_ID"
gh run watch "$RUN_ID" -R "$GITHUB_REPO" --exit-status

echo
echo "Uploaded. TestFlight shows the new build after Apple's processing (usually 5-15 minutes)."
