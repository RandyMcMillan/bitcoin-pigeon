#!/bin/sh

set -eu

PROJECT="swiftyapp/swiftyapp.xcodeproj"
SCHEME="swiftyapp"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    BUILD_DIR="$(pwd)/build" \
    build
