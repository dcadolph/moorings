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

app: $(ICNS)
	swift build -c release $(ARCH_FLAGS)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(ICNS) $(APP)/Contents/Resources/AppIcon.icns
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
