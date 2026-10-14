#!/bin/sh

set -eu

PROJECT="swiftyapp/swiftyapp.xcodeproj"
SCHEME="swiftyapp"
BUILD_DIR="$(pwd)/build"
APP_NAME="swiftyapp.app"
APP_PATH="$BUILD_DIR/Release-maccatalyst/$APP_NAME"

CHECK_ONLY=0
NOTARIZE=0
TAG=""
APPLE_ID_DEFAULT="randymcmillan1@mac.com"
APPLE_ID="${APPLE_ID:-$APPLE_ID_DEFAULT}"
TEAM_ID="${TEAM_ID:-}"
PASSWORD="${NOTARY_PASSWORD:-${PASSWORD:-}}"
SIGNING_IDENTITY_DEFAULT="Developer ID Application: Randy McMillan (M684FYCYG6)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$SIGNING_IDENTITY_DEFAULT}"

usage() {
  echo "Usage: $0 [--check] [--notarize] [--apple-id EMAIL] [--team-id TEAM] [--password PASS] [tag]" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)
      CHECK_ONLY=1
      ;;
    --notarize)
      NOTARIZE=1
      ;;
    --apple-id)
      shift
      [ $# -gt 0 ] || usage
      APPLE_ID="$1"
      ;;
    --team-id)
      shift
      [ $# -gt 0 ] || usage
      TEAM_ID="$1"
      ;;
    --password)
      shift
      [ $# -gt 0 ] || usage
      PASSWORD="$1"
      ;;
    --signing-identity)
      shift
      [ $# -gt 0 ] || usage
      SIGNING_IDENTITY="$1"
      ;;
    --help|-h)
      usage
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [ -n "$TAG" ]; then
        echo "Unexpected extra argument: $1" >&2
        usage
      fi
      TAG="$1"
      ;;
  esac
  shift
done

if [ "$CHECK_ONLY" -eq 0 ] && [ -z "$TAG" ]; then
  TAG_VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/{print $3; exit}')
  if [ -z "$TAG_VERSION" ]; then
    echo "Unable to determine MARKETING_VERSION from the Xcode project." >&2
    exit 1
  fi
  TAG="v${TAG_VERSION}"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  if [ ! -d "$APP_PATH" ]; then
    echo "Missing app bundle: $APP_PATH" >&2
    exit 1
  fi

  codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n '1,40p'
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
  exit 0
fi

ZIP_NAME="$BUILD_DIR/bitcoin-pigeon-${TAG}.zip"

./BuildRelease.sh

if [ -z "$SIGNING_IDENTITY" ]; then
  if [ "$NOTARIZE" -eq 1 ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | awk '/Developer ID Application:/{print $2; exit}')
  else
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | awk '/Apple Development:/{print $2; exit}')
  fi
fi
if [ -z "$SIGNING_IDENTITY" ]; then
  if [ "$NOTARIZE" -eq 1 ]; then
    echo "No Developer ID Application signing identity was found in your keychain." >&2
    echo "Install a Developer ID Application certificate, or rerun without --notarize for local signing only." >&2
  else
    echo "Unable to find an Apple Development codesigning identity. Set SIGNING_IDENTITY and retry." >&2
  fi
  security find-identity -v -p codesigning >&2
  exit 1
fi

if [ -z "$TEAM_ID" ]; then
  TEAM_ID=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null | awk '/DEVELOPMENT_TEAM/{print $3; exit}')
fi
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="M684FYCYG6"
fi

find "$APP_PATH/Contents/Frameworks" -name '*.cstemp' -delete

for FRAMEWORK in "$APP_PATH"/Contents/Frameworks/*.framework; do
  if [ -d "$FRAMEWORK" ]; then
    if [ "$NOTARIZE" -eq 1 ]; then
      codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$FRAMEWORK"
    else
      codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --options runtime "$FRAMEWORK"
    fi
  fi
done

if [ "$NOTARIZE" -eq 1 ]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime "$APP_PATH"
else
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --options runtime "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [ "$NOTARIZE" -eq 1 ]; then
  if [ -z "$APPLE_ID" ]; then
    echo "Missing --apple-id (or APPLE_ID)." >&2
    exit 1
  fi
  if [ -z "$PASSWORD" ]; then
    echo "Missing --password (or NOTARY_PASSWORD)." >&2
    exit 1
  fi

  NOTARIZE_ZIP="$BUILD_DIR/bitcoin-pigeon-${TAG}-notarize.zip"
  ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
  xcrun notarytool submit "$NOTARIZE_ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$PASSWORD" \
    --wait
  xcrun stapler staple "$APP_PATH"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  spctl --assess --type execute --verbose=4 "$APP_PATH"
fi

ditto -c -k --keepParent "$APP_PATH" "$ZIP_NAME"

if [ "$NOTARIZE" -eq 1 ] && ! git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  git push origin "refs/tags/$TAG"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$ZIP_NAME" --clobber
else
  gh release create "$TAG" \
    --title "bitcoin-pigeon ${TAG}" \
    --generate-notes \
    "$ZIP_NAME"
fi

REPO_NAME_WITH_OWNER=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
ASSET_NAME=$(basename "$ZIP_NAME")
RELEASE_ASSET_URL="https://github.com/${REPO_NAME_WITH_OWNER}/releases/download/${TAG}/${ASSET_NAME}"
echo "Release asset: ${RELEASE_ASSET_URL}"
