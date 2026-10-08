#!/usr/bin/env bash

set -ex

xcodebuild -version
xcodebuild -project switchy.xcodeproj -scheme Release -showBuildSettings | grep SWIFT_VERSION

set -o pipefail && xcodebuild test -project switchy.xcodeproj -scheme Test -configuration Release | scripts/xcbeautify
