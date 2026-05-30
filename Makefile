SHELL := /bin/bash

PROJECT := swiftyapp/swiftyapp.xcodeproj
SCHEME := swiftyapp
BUILD_SCRIPT := ./build.sh
RUST_CRATE_DIR := rustylib
SWIFT_PACKAGE_DIR := swiftyapp/Lib/swiftyrustlib
SWIFT_PACKAGE_BUILD_DIR := .build/swift-test
ICON_SOURCE := assets/icon.png
TOR_ICON_SOURCE := assets/icon-tor.png
ICONSET_DIR := swiftyapp/swiftyapp/Assets.xcassets/AppIcon.appiconset
TOR_ICONSET_DIR := swiftyapp/swiftyapp/Assets.xcassets/AppIconTor.appiconset
DERIVED_DATA ?= .build/xcode
CONFIGURATION ?= Debug
APP_NAME := swiftyapp.app
INSTALL_DIR ?= $(HOME)/Applications
SYMROOT := $(abspath $(DERIVED_DATA))
OBJROOT := $(SYMROOT)/Intermediates.noindex
HOST_ARCH := $(shell uname -m)
SIMULATOR_ARCH := $(if $(filter arm64,$(HOST_ARCH)),arm64,x86_64)
IOS_DESTINATION ?= generic/platform=iOS Simulator
CATALYST_DESTINATION ?= generic/platform=macOS,variant=Mac Catalyst
CATALYST_APP_PATH := $(SYMROOT)/$(CONFIGURATION)-maccatalyst/$(APP_NAME)

.DEFAULT_GOAL := help

.PHONY: help rust icons icons-tor art test test-tor resolve app catalyst install clean
.PHONY: test-relay-nocapture

help:
	@printf '%s\n' \
		'make rust      - build the Rust library, bindings, and XCFramework' \
		'make icons     - generate iOS and macOS app icons from assets/icon.png' \
		'make icons-tor - generate iOS and macOS tor icons from assets/icon-tor.png' \
		'make art       - generate the tor/art image sets from assets/*.png' \
		'make test      - build Rust and run the live Swift package test' \
		'make test-tor  - run the live Swift package test with Tor-only fanout' \
		'make test-relay-nocapture - run the visible 60s relay nocapture test' \
		'make resolve   - resolve local Swift package dependencies' \
		'make app       - build the iOS app for a generic simulator destination' \
		'make catalyst  - build the app for Mac Catalyst' \
		'make install   - install the Mac Catalyst app into ~/Applications' \
		'make clean     - clean Rust and Xcode build artifacts'

rust:
	$(BUILD_SCRIPT)

icons:
	@set -euo pipefail; \
	mkdir -p "$(ICONSET_DIR)"; \
	rm -f "$(ICONSET_DIR)"/*.png; \
	for spec in \
		"iphone_20x20@2x.png:40" \
		"iphone_20x20@3x.png:60" \
		"iphone_29x29@2x.png:58" \
		"iphone_29x29@3x.png:87" \
		"iphone_40x40@2x.png:80" \
		"iphone_40x40@3x.png:120" \
		"iphone_60x60@2x.png:120" \
		"iphone_60x60@3x.png:180" \
		"ipad_20x20@1x.png:20" \
		"ipad_20x20@2x.png:40" \
		"ipad_29x29@1x.png:29" \
		"ipad_29x29@2x.png:58" \
		"ipad_40x40@1x.png:40" \
		"ipad_40x40@2x.png:80" \
		"ipad_76x76@1x.png:76" \
		"ipad_76x76@2x.png:152" \
		"ipad_83.5x83.5@2x.png:167" \
		"mac_16x16@1x.png:16" \
		"mac_16x16@2x.png:32" \
		"mac_32x32@1x.png:32" \
		"mac_32x32@2x.png:64" \
		"mac_128x128@1x.png:128" \
		"mac_128x128@2x.png:256" \
		"mac_256x256@1x.png:256" \
		"mac_256x256@2x.png:512" \
		"mac_512x512@1x.png:512" \
		"mac_512x512@2x.png:1024" \
		"ios-marketing_1024x1024@1x.png:1024"; do \
		name="$${spec%%:*}"; \
		size="$${spec##*:}"; \
		sips -z "$$size" "$$size" "$(ICON_SOURCE)" --out "$(ICONSET_DIR)/$$name" >/dev/null; \
	done

icons-tor:
	@set -euo pipefail; \
	mkdir -p "$(TOR_ICONSET_DIR)"; \
	rm -f "$(TOR_ICONSET_DIR)"/*.png; \
	for spec in \
		"iphone_20x20@2x.png:40" \
		"iphone_20x20@3x.png:60" \
		"iphone_29x29@2x.png:58" \
		"iphone_29x29@3x.png:87" \
		"iphone_40x40@2x.png:80" \
		"iphone_40x40@3x.png:120" \
		"iphone_60x60@2x.png:120" \
		"iphone_60x60@3x.png:180" \
		"ipad_20x20@1x.png:20" \
		"ipad_20x20@2x.png:40" \
		"ipad_29x29@1x.png:29" \
		"ipad_29x29@2x.png:58" \
		"ipad_40x40@1x.png:40" \
		"ipad_40x40@2x.png:80" \
		"ipad_76x76@1x.png:76" \
		"ipad_76x76@2x.png:152" \
		"ipad_83.5x83.5@2x.png:167" \
		"mac_16x16@1x.png:16" \
		"mac_16x16@2x.png:32" \
		"mac_32x32@1x.png:32" \
		"mac_32x32@2x.png:64" \
		"mac_128x128@1x.png:128" \
		"mac_128x128@2x.png:256" \
		"mac_256x256@1x.png:256" \
		"mac_256x256@2x.png:512" \
		"mac_512x512@1x.png:512" \
		"mac_512x512@2x.png:1024" \
		"ios-marketing_1024x1024@1x.png:1024"; do \
		name="$${spec%%:*}"; \
		size="$${spec##*:}"; \
		sips -z "$$size" "$$size" "$(TOR_ICON_SOURCE)" --out "$(TOR_ICONSET_DIR)/$$name" >/dev/null; \
	done

art:
	@set -euo pipefail; \
	gen_imageset() { \
		source="$$1"; \
		dir="$$2"; \
		base="$$(basename "$$source" .png)"; \
		width="$$(sips -g pixelWidth "$$source" | awk '/pixelWidth/ {print $$2; exit}')"; \
		height="$$(sips -g pixelHeight "$$source" | awk '/pixelHeight/ {print $$2; exit}')"; \
		mkdir -p "$$dir"; \
		rm -f "$$dir/$$base.png" "$$dir/$$base@2x.png" "$$dir/$$base@3x.png"; \
		sips -z "$$height" "$$width" "$$source" --out "$$dir/$$base.png" >/dev/null; \
		sips -z "$$((height * 2))" "$$((width * 2))" "$$source" --out "$$dir/$$base@2x.png" >/dev/null; \
		sips -z "$$((height * 3))" "$$((width * 3))" "$$source" --out "$$dir/$$base@3x.png" >/dev/null; \
	}; \
	gen_imageset assets/icon-tor.png swiftyapp/swiftyapp/Assets.xcassets/icon-tor.imageset; \
	gen_imageset assets/icon-tor-gray.png swiftyapp/swiftyapp/Assets.xcassets/icon-tor-gray.imageset; \
	gen_imageset assets/icon-spread.png swiftyapp/swiftyapp/Assets.xcassets/icon-spread.imageset; \
	gen_imageset assets/icon-spread-tor.png swiftyapp/swiftyapp/Assets.xcassets/icon-spread-tor.imageset; \
	gen_imageset assets/icon-spread-tor-purple.png swiftyapp/swiftyapp/Assets.xcassets/icon-spread-tor-purple.imageset; \
	gen_imageset assets/icon-carrier-tor.png swiftyapp/swiftyapp/Assets.xcassets/icon-carrier-tor.imageset; \
	gen_imageset assets/icon-carrier-tor-gray.png swiftyapp/swiftyapp/Assets.xcassets/icon-carrier-tor-gray.imageset; \
	gen_imageset assets/carrier-tor-purple.png swiftyapp/swiftyapp/Assets.xcassets/carrier-tor-purple.imageset; \
	gen_imageset assets/art1.png swiftyapp/swiftyapp/Assets.xcassets/art1.imageset; \
	gen_imageset assets/art2.png swiftyapp/swiftyapp/Assets.xcassets/art2.imageset; \
	gen_imageset assets/portrait1.png swiftyapp/swiftyapp/Assets.xcassets/portrait1.imageset; \
	gen_imageset assets/square-art1.png swiftyapp/swiftyapp/Assets.xcassets/square-art1.imageset; \
	gen_imageset assets/square2.png swiftyapp/swiftyapp/Assets.xcassets/square2.imageset

test: rust
	cd "$(SWIFT_PACKAGE_DIR)" && swift test --build-path "../../$(SWIFT_PACKAGE_BUILD_DIR)"

test-tor: rust
	cd "$(SWIFT_PACKAGE_DIR)" && TOR_ONLY=1 swift test --build-path "../../$(SWIFT_PACKAGE_BUILD_DIR)"

test-relay-nocapture: rust
	cd tx-pigeon && cargo test --test relay_nocapture -- --nocapture --exact relay_nocapture_60_seconds --test-threads=1

resolve:
	xcodebuild -resolvePackageDependencies -project "$(PROJECT)" -scheme "$(SCHEME)"

app: rust resolve
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		SYMROOT="$(SYMROOT)" \
		OBJROOT="$(OBJROOT)" \
		-destination "$(IOS_DESTINATION)" \
		ARCHS="$(SIMULATOR_ARCH)" \
		ONLY_ACTIVE_ARCH=YES \
		build

catalyst: rust resolve
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		SYMROOT="$(SYMROOT)" \
		OBJROOT="$(OBJROOT)" \
		-destination "$(CATALYST_DESTINATION)" \
		ARCHS="$(HOST_ARCH)" \
		ONLY_ACTIVE_ARCH=YES \
		build

install: catalyst
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	cp -R "$(CATALYST_APP_PATH)" "$(INSTALL_DIR)/$(APP_NAME)"

clean:
	cd "$(RUST_CRATE_DIR)" && cargo clean
	rm -rf "$(DERIVED_DATA)"
