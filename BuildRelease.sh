#!/bin/sh

set -eu

PROJECT="swiftyapp/swiftyapp.xcodeproj"
SCHEME="swiftyapp"
HOST_ARCH="$(uname -m)"

./build.sh

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    ARCHS="$HOST_ARCH" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    BUILD_DIR="$(pwd)/build" \
    build
