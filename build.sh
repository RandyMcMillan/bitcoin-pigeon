set -euo pipefail

# Xcode runs build phases in a non-login shell, so Cargo/Rustup may not be on PATH.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1090
    . "$HOME/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo not found; install Rust or add cargo to PATH" >&2
    exit 127
fi

if ! command -v rustup >/dev/null 2>&1; then
    echo "rustup not found; install Rust or add rustup to PATH" >&2
    exit 127
fi

MY_CRATE=rustylib
SWIFT_APP=swiftyapp
SWIFT_PROJECT=swiftyrustlib
SWIFT_PROJECT_NAME=RustyLib
SWIFT_CORE_NAME=RustyCore
ICON_SPECS=(
    "iphone_20x20@2x.png:40"
    "iphone_20x20@3x.png:60"
    "iphone_29x29@2x.png:58"
    "iphone_29x29@3x.png:87"
    "iphone_40x40@2x.png:80"
    "iphone_40x40@3x.png:120"
    "iphone_60x60@2x.png:120"
    "iphone_60x60@3x.png:180"
    "ipad_20x20@1x.png:20"
    "ipad_20x20@2x.png:40"
    "ipad_29x29@1x.png:29"
    "ipad_29x29@2x.png:58"
    "ipad_40x40@1x.png:40"
    "ipad_40x40@2x.png:80"
    "ipad_76x76@1x.png:76"
    "ipad_76x76@2x.png:152"
    "ipad_83.5x83.5@2x.png:167"
    "mac_16x16@1x.png:16"
    "mac_16x16@2x.png:32"
    "mac_32x32@1x.png:32"
    "mac_32x32@2x.png:64"
    "mac_128x128@1x.png:128"
    "mac_128x128@2x.png:256"
    "mac_256x256@1x.png:256"
    "mac_256x256@2x.png:512"
    "mac_512x512@1x.png:512"
    "mac_512x512@2x.png:1024"
    "ios-marketing_1024x1024@1x.png:1024"
)

generate_iconset() {
    local source="$1"
    local dir="$2"

    mkdir -p "${dir}"
    rm -f "${dir}"/*.png

    local spec name size
    for spec in "${ICON_SPECS[@]}"; do
        name="${spec%%:*}"
        size="${spec##*:}"
        sips -z "$size" "$size" "${source}" --out "${dir}/${name}" >/dev/null
    done
}

cd $MY_CRATE

# step 1 - compile rust library and generate bindings
HEADERPATH="out/${MY_CRATE}FFI.h"
TARGETDIR="$(cargo metadata --no-deps --format-version 1 | tr -d '\n' | sed -n 's/.*"target_directory":"\([^"]*\)".*/\1/p')"
TARGETDIR="${TARGETDIR:-target}"
RELDIR="release"
STATIC_LIB_NAME="lib${MY_CRATE}.a"
NEW_HEADER_DIR="out/include"
XCFRAMEWORK_PATH="${MY_CRATE}_framework.xcframework"

DEVICE_TARGET="aarch64-apple-ios"

case "$(uname -m)" in
    arm64)
        SIMULATOR_TARGET="aarch64-apple-ios-sim"
        CATALYST_TARGET="aarch64-apple-ios-macabi"
        MACOS_TARGET="aarch64-apple-darwin"
        ;;
    x86_64)
        SIMULATOR_TARGET="x86_64-apple-ios"
        CATALYST_TARGET="x86_64-apple-ios-macabi"
        MACOS_TARGET="x86_64-apple-darwin"
        ;;
    *)
        echo "Unsupported host architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

targets=("${DEVICE_TARGET}" "${SIMULATOR_TARGET}" "${CATALYST_TARGET}" "${MACOS_TARGET}")

for target in "${targets[@]}"; do
    rustup target add ${target}
            cargo build --target "${target}" --release -j8
            cargo run --bin uniffi-bindgen generate --library "${TARGETDIR}/${target}/${RELDIR}/${STATIC_LIB_NAME}" --language swift --out-dir out
        done
# step 2 - create xcframework
mkdir -p "${NEW_HEADER_DIR}"
cp "${HEADERPATH}" "${NEW_HEADER_DIR}/"
cp "out/${MY_CRATE}FFI.modulemap" "${NEW_HEADER_DIR}/module.modulemap"

rm -rf "${XCFRAMEWORK_PATH}"

xcodebuild -create-xcframework \
    -library "${TARGETDIR}/${DEVICE_TARGET}/${RELDIR}/${STATIC_LIB_NAME}" -headers "${NEW_HEADER_DIR}" \
    -library "${TARGETDIR}/${SIMULATOR_TARGET}/${RELDIR}/${STATIC_LIB_NAME}" -headers "${NEW_HEADER_DIR}" \
    -library "${TARGETDIR}/${CATALYST_TARGET}/${RELDIR}/${STATIC_LIB_NAME}" -headers "${NEW_HEADER_DIR}" \
    -library "${TARGETDIR}/${MACOS_TARGET}/${RELDIR}/${STATIC_LIB_NAME}" -headers "${NEW_HEADER_DIR}" \
    -output "${XCFRAMEWORK_PATH}"

rm -rf "${NEW_HEADER_DIR}"

cd ../

generate_iconset "./assets/icon.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/AppIcon.appiconset"
generate_iconset "./assets/icon-tor.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/AppIconTor.appiconset"

SWIFT_LIB_PATH="./${SWIFT_APP}/Lib/${SWIFT_PROJECT}"
SWIFT_ARTIFACTS_PATH="${SWIFT_LIB_PATH}/artifacts"
SWIFT_SOURCES_PATH="${SWIFT_LIB_PATH}/Sources/${SWIFT_PROJECT_NAME}"

# step 3 - move to SwiftLib artifacts
mkdir -p "${SWIFT_ARTIFACTS_PATH}"
rm -rf "${SWIFT_ARTIFACTS_PATH}/${SWIFT_CORE_NAME}.xcframework"
cp -R "./${MY_CRATE}/${XCFRAMEWORK_PATH}" "${SWIFT_ARTIFACTS_PATH}/${SWIFT_CORE_NAME}.xcframework"

# step 4 - move to SwiftLib Sources
mkdir -p "${SWIFT_SOURCES_PATH}"
cp "./${MY_CRATE}/out/${MY_CRATE}.swift" "${SWIFT_SOURCES_PATH}/${SWIFT_PROJECT_NAME}.swift"
