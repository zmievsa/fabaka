default:
    @just --list

# Build build/Fabaka.app (swiftc via the Makefile).
build:
    make all

# Build, copy to /Applications and start it.
install:
    make install

# End-to-end tests against a stand-in busy app; stops the installed Fabaka for ~2 minutes.
test *tests:
    make test TESTS="{{tests}}"

# Stream Fabaka's log.
logs:
    make logs

# Bump CFBundleShortVersionString in Info.plist first. Notarizes, publishes a GitHub release, bumps the cask.
release:
    make release

# Deploy site/public to fabaka.dev, then check the live page answers.
deploy:
    make site
    curl -fsS -o /dev/null https://fabaka.dev/ && echo "fabaka.dev is up"
