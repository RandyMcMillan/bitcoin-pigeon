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

CLEAN=false
for arg in "$@"; do
    case "${arg}" in
        --clean)
            CLEAN=true
            ;;
        -h|--help)
            echo "Usage: $0 [--clean]"
            exit 0
            ;;
        *)
            echo "Unknown option: ${arg}" >&2
            exit 64
            ;;
    esac
done

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

generate_imageset() {
    local source="$1"
    local dir="$2"
    local base
    local width
    local height

    base="$(basename "${source}" .png)"
    width="$(sips -g pixelWidth "${source}" | awk '/pixelWidth/ {print $2; exit}')"
    height="$(sips -g pixelHeight "${source}" | awk '/pixelHeight/ {print $2; exit}')"

    mkdir -p "${dir}"
    rm -f "${dir}/${base}.png" "${dir}/${base}@2x.png" "${dir}/${base}@3x.png"

    sips -z "${height}" "${width}" "${source}" --out "${dir}/${base}.png" >/dev/null
    sips -z "$((height * 2))" "$((width * 2))" "${source}" --out "${dir}/${base}@2x.png" >/dev/null
    sips -z "$((height * 3))" "$((width * 3))" "${source}" --out "${dir}/${base}@3x.png" >/dev/null
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
        SIMULATOR_TARGETS=("aarch64-apple-ios-sim" "x86_64-apple-ios")
        CATALYST_TARGET="aarch64-apple-ios-macabi"
        MACOS_TARGET="aarch64-apple-darwin"
        ;;
    x86_64)
        SIMULATOR_TARGETS=("x86_64-apple-ios")
        CATALYST_TARGET="x86_64-apple-ios-macabi"
        MACOS_TARGET="x86_64-apple-darwin"
        ;;
    *)
        echo "Unsupported host architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

targets=("${DEVICE_TARGET}" "${SIMULATOR_TARGETS[@]}" "${CATALYST_TARGET}" "${MACOS_TARGET}")

if ${CLEAN}; then
    rm -rf "${MY_CRATE}/out" "${MY_CRATE}/${XCFRAMEWORK_PATH}"
    for target in "${targets[@]}"; do
        rm -rf "${TARGETDIR}/${target}"
    done
fi

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

SIMULATOR_LIB_PATH="${TARGETDIR}/simulator-${RELDIR}/${STATIC_LIB_NAME}"
mkdir -p "$(dirname "${SIMULATOR_LIB_PATH}")"

if [ "${#SIMULATOR_TARGETS[@]}" -gt 1 ]; then
    lipo -create \
        "${TARGETDIR}/${SIMULATOR_TARGETS[0]}/${RELDIR}/${STATIC_LIB_NAME}" \
        "${TARGETDIR}/${SIMULATOR_TARGETS[1]}/${RELDIR}/${STATIC_LIB_NAME}" \
        -output "${SIMULATOR_LIB_PATH}"
else
    cp "${TARGETDIR}/${SIMULATOR_TARGETS[0]}/${RELDIR}/${STATIC_LIB_NAME}" "${SIMULATOR_LIB_PATH}"
fi

xcframework_args=(
    -library "${TARGETDIR}/${DEVICE_TARGET}/${RELDIR}/${STATIC_LIB_NAME}" -headers "${NEW_HEADER_DIR}"
    -library "${SIMULATOR_LIB_PATH}" -headers "${NEW_HEADER_DIR}"
    -library "${TARGETDIR}/${CATALYST_TARGET}/${RELDIR}/${STATIC_LIB_NAME}" -headers "${NEW_HEADER_DIR}"
    -library "${TARGETDIR}/${MACOS_TARGET}/${RELDIR}/${STATIC_LIB_NAME}" -headers "${NEW_HEADER_DIR}"
    -output "${XCFRAMEWORK_PATH}"
)

xcodebuild -create-xcframework "${xcframework_args[@]}"

rm -rf "${NEW_HEADER_DIR}"

cd ../

generate_iconset "./assets/icon.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/AppIcon.appiconset"
generate_iconset "./assets/icon-tor.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/AppIconTor.appiconset"

generate_imageset "./assets/icon-tor.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/icon-tor.imageset"
generate_imageset "./assets/icon-tor-gray.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/icon-tor-gray.imageset"
generate_imageset "./assets/icon-spread.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/icon-spread.imageset"
generate_imageset "./assets/icon-spread-tor.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/icon-spread-tor.imageset"
generate_imageset "./assets/icon-spread-tor-purple.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/icon-spread-tor-purple.imageset"
generate_imageset "./assets/icon-carrier-tor.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/icon-carrier-tor.imageset"
generate_imageset "./assets/icon-carrier-tor-gray.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/icon-carrier-tor-gray.imageset"
generate_imageset "./assets/carrier-tor-purple.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/carrier-tor-purple.imageset"
generate_imageset "./assets/art1.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/art1.imageset"
generate_imageset "./assets/art2.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/art2.imageset"
generate_imageset "./assets/portrait1.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/portrait1.imageset"
generate_imageset "./assets/square-art1.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/square-art1.imageset"
generate_imageset "./assets/square2.png" "./${SWIFT_APP}/swiftyapp/Assets.xcassets/square2.imageset"

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
