APP     := Flick
BUNDLE  := build/$(APP).app
BIN     := $(BUNDLE)/Contents/MacOS/$(APP)
SDK     := $(shell xcrun --show-sdk-path)
SOURCES := $(wildcard Sources/*.swift)
# Signing with a real certificate keeps the Accessibility grant across rebuilds.
SIGN_ID ?= $(shell security find-identity -v -p codesigning | awk '/Apple Development/ {print $$2; exit}')

.PHONY: all install uninstall run logs clean

all: $(BUNDLE)

$(BUNDLE): $(SOURCES) Info.plist
	@mkdir -p $(BUNDLE)/Contents/MacOS
	swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -sdk $(SDK) \
		-F $(SDK)/System/Library/PrivateFrameworks -framework SkyLight \
		$(SOURCES) -o $(BIN)
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force --sign "$(if $(SIGN_ID),$(SIGN_ID),-)" $(BUNDLE)

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
