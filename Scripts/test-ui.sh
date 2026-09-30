#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
portfolio_simulator_id=${PORTFOLIO_SIMULATOR_ID:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; devices=json.load(sys.stdin)["devices"]; print(next(d["udid"] for group in devices.values() for d in group if d["name"].startswith("iPhone")))')}
xcodebuild -project 'Podcast Pocket.xcodeproj' -scheme 'Podcast Pocket' \
  -destination "platform=iOS Simulator,id=$portfolio_simulator_id" -parallel-testing-enabled NO -collect-test-diagnostics never -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -derivedDataPath build -resultBundlePath "build/Workflow-$(date +%s).xcresult" test
