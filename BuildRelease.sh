#!/bin/sh

xcodebuild \
    -workspace workspace.xcworkspace \
    -scheme "Disk Inventory X" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    BUILD_DIR="$(pwd)/build" \
    build
