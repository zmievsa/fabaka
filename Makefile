APP     := Flick
BUNDLE  := build/$(APP).app
BIN     := $(BUNDLE)/Contents/MacOS/$(APP)
SDK     := $(shell xcrun --show-sdk-path)
SOURCES := $(wildcard Sources/*.swift)
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
ZIP     := build/$(APP)-$(VERSION).zip
TAP     := zmievsa/homebrew-tap
# A real certificate keeps the Accessibility grant across rebuilds. Developer ID comes first, so a local
# build shares its grant with the Homebrew build. With no certificate the build is signed ad hoc.
SIGN_ID ?= $(shell security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $$2; exit}')
SIGN_ID := $(or $(SIGN_ID),$(shell security find-identity -v -p codesigning | awk '/Apple Development/ {print $$2; exit}'))
SIGN    := $(if $(SIGN_ID),--sign $(SIGN_ID) --options runtime --timestamp,--sign -)

.PHONY: all install uninstall run logs clean release

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) Info.plist
	@mkdir -p $(BUNDLE)/Contents/MacOS
	swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -sdk $(SDK) \
		-F $(SDK)/System/Library/PrivateFrameworks -framework SkyLight \
		$(SOURCES) -o $(BIN)
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force $(SIGN) $(BUNDLE)

install: all
	@pkill -x $(APP) || true
	rm -rf /Applications/$(APP).app
	cp -R $(BUNDLE) /Applications/$(APP).app
	open /Applications/$(APP).app

uninstall:
	@pkill -x $(APP) || true
	rm -rf /Applications/$(APP).app

run: all
	$(BIN)

logs:
	log stream --level debug --predicate 'subsystem == "com.zmievsa.flick"'

clean:
	rm -rf build

# Bump CFBundleShortVersionString in Info.plist first. Needs the Developer ID certificate and the
# `flick-notary` notarytool profile in the keychain. Publishes a GitHub release and bumps the Homebrew cask.
release: clean all
	codesign --verify --strict $(BUNDLE)
	codesign -dvv $(BUNDLE) 2>&1 | grep -q 'Authority=Developer ID Application' || { echo "Not signed with Developer ID"; exit 1; }
	ditto -c -k --keepParent $(BUNDLE) build/notarize.zip
	xcrun notarytool submit build/notarize.zip --keychain-profile flick-notary --wait
	xcrun stapler staple $(BUNDLE)
	spctl --assess --type execute -v $(BUNDLE)
	ditto -c -k --keepParent $(BUNDLE) $(ZIP)
	gh release create v$(VERSION) $(ZIP) --title "Flick $(VERSION)" --generate-notes
	gh repo clone $(TAP) build/tap -- --depth 1
	sed -i '' -e 's/^  version ".*"/  version "$(VERSION)"/' \
		-e "s/^  sha256 \".*\"/  sha256 \"$$(shasum -a 256 $(ZIP) | cut -d' ' -f1)\"/" build/tap/Casks/flick.rb
	git -C build/tap commit -am "flick $(VERSION)"
	git -C build/tap push
