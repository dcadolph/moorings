APP := .build/Moorings.app
SANDBOX_APP := .build/sandbox/Moorings.app
SIGN_ID ?= -
ENTITLEMENTS ?=
BUILD ?= 1
VERSION ?=
MOORINGS_SUPPORT_URL ?=
PLIST := $(APP)/Contents/Info.plist
ARCHS ?=
ARCH_FLAGS := $(foreach arch,$(ARCHS),--arch $(arch))
ZIP ?= .build/Moorings.zip
DMG ?= .build/Moorings.dmg
DMGBUILD ?= dmgbuild
NOTARY_PROFILE ?= moorings
SIGN_FLAGS := --options runtime $(if $(filter-out -,$(SIGN_ID)),--timestamp)

ICONSET := .build/AppIcon.iconset
ICNS := .build/AppIcon.icns

# INTENTS_PROTOCOLS lists the protocols whose conformances the compiler records for Shortcuts.
INTENTS_PROTOCOLS := .build/intents-protocols.json
INTENTS_FLAGS := -Xswiftc -emit-const-values -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file \
	-Xswiftc -Xfrontend -Xswiftc $(INTENTS_PROTOCOLS)
INTENTS_OUT := .build/intents
# INTENTS_CONSTS is where the compiler leaves the app module's recorded conformances, which differs
# between a one-architecture build and a universal one.
INTENTS_CONSTS := $(if $(ARCHS),.build/apple/Intermediates.noindex/Moorings.build/Release/Moorings.build/Objects-normal/$(firstword $(ARCHS))/Moorings-primary.swiftconstvalues,.build/$(shell uname -m)-apple-macosx/release/Moorings.build/Moorings.swiftconstvalues)

.PHONY: build test app sandbox zip dmg notarize run clean

build:
	swift build

test:
	swift build
	swift test

$(ICNS): ../app-icon.png
	rm -rf $(ICONSET)
	mkdir -p $(ICONSET)
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size ../app-icon.png --out $(ICONSET)/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) ../app-icon.png --out $(ICONSET)/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o $(ICNS)

$(INTENTS_PROTOCOLS):
	mkdir -p .build
	printf '%s' '["AppIntent","AppEntity","AppEnum","EntityQuery","DynamicOptionsProvider","AppShortcutsProvider"]' > $@

app: $(ICNS) $(INTENTS_PROTOCOLS)
	swift build -c release $(ARCH_FLAGS) $(INTENTS_FLAGS)
	rm -rf $(APP) $(INTENTS_OUT)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources $(INTENTS_OUT)
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
	ls Sources/Moorings/*.swift | sed "s|^|$$PWD/|" > $(INTENTS_OUT)/sources.txt
	echo "$$PWD/$(INTENTS_CONSTS)" > $(INTENTS_OUT)/consts.txt
	test -f $(INTENTS_CONSTS)
	xcrun appintentsmetadataprocessor --output $(APP)/Contents/Resources \
		--toolchain-dir "$$(dirname "$$(dirname "$$(dirname "$$(xcrun --find swift)")")")" --module-name Moorings \
		--sdk-root "$$(xcrun --sdk macosx --show-sdk-path)" \
		--xcode-version "$$(xcodebuild -version | awk '/Build version/ {print $$3}')" --platform-family macOS \
		--deployment-target 14.0 --target-triple arm64-apple-macos14.0 --source-file-list $(INTENTS_OUT)/sources.txt \
		--swift-const-vals-list $(INTENTS_OUT)/consts.txt
	test -f $(APP)/Contents/Resources/Metadata.appintents/extract.actionsdata
	cp "$$(swift build -c release $(ARCH_FLAGS) --show-bin-path)/Moorings" $(APP)/Contents/MacOS/Moorings
	cp Sources/Moorings/Info.plist $(PLIST)
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion '$(BUILD)'" $(PLIST)
	$(if $(VERSION),/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString '$(VERSION)'" $(PLIST))
	/usr/libexec/PlistBuddy -c "Set :MooringsSupportURL '$(MOORINGS_SUPPORT_URL)'" $(PLIST)
	codesign --force --sign "$(SIGN_ID)" $(SIGN_FLAGS) $(if $(ENTITLEMENTS),--entitlements $(ENTITLEMENTS)) $(APP)

sandbox:
	$(MAKE) app APP=$(SANDBOX_APP) ENTITLEMENTS=sandbox.entitlements

zip: app
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)

dmg:
	rm -f $(DMG)
	$(DMGBUILD) -s dmg.py -D app=$(APP) "Moorings" $(DMG)
	$(if $(filter-out -,$(SIGN_ID)),codesign --force --sign "$(SIGN_ID)" --timestamp $(DMG))

notarize: zip
	xcrun notarytool submit $(ZIP) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP)
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP) $(ZIP)

run: app
	-pkill -x Moorings
	open $(APP)

clean:
	rm -rf .build
