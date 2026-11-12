#!/bin/zsh
# End-to-end tests: the real Flick build against BusyApp, a stand-in for an app that is still busy at login.
# Each test asserts what the Switcher would list, read through Flick's USR1 dump, without activating BusyApp.
# Run with `make test`. It stops the installed Flick for about two minutes and starts it again at the end.
set -u
cd "${0:A:h}/.."

FLICK=build/Flick.app
BUSY=build/test/BusyApp.app
WORK=$(mktemp -d)
FAILED=0

build_busy_app() {
    mkdir -p $BUSY/Contents/MacOS
    swiftc -O -target arm64-apple-macos26.0 Tests/BusyApp.swift -o $BUSY/Contents/MacOS/BusyApp || exit 1
    cat > $BUSY/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BusyApp</string>
<key>CFBundleIdentifier</key><string>com.zmievsa.flick.test.busyapp</string>
<key>CFBundleName</key><string>BusyApp</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSSupportsAutomaticTermination</key><false/>
</dict></plist>
EOF
    codesign --force --sign - $BUSY
}

cleanup() {
    pkill -CONT -x BusyApp
    pkill -x BusyApp
    pkill -x Flick
    rm -rf $WORK
    [[ -d /Applications/Flick.app ]] && open /Applications/Flick.app
}
trap cleanup EXIT

wait_for() { # seconds, shell condition
    local deadline=$((SECONDS + $1))
    until eval "$2"; do
        (( SECONDS >= deadline )) && return 1
        /bin/sleep 0.5
    done
}

start_flick() {
    pkill -x Flick
    wait_for 10 "! pgrep -x Flick > /dev/null" || { print "Old Flick didn't quit"; return 1; }
    open $FLICK
    wait_for 10 "pgrep -x Flick > /dev/null" || { print "Flick didn't launch"; return 1; }
    # SIGUSR1 kills Flick until its first line of code ignores it, so give it time before any dump.
    /bin/sleep 2
}

# Launches BusyApp in the background, never activating it, and waits for it to start.
launch_busy_app() { # title [unready flag]
    pkill -x BusyApp
    open -n -g --env FLICK_TEST_TITLE="$1" --env FLICK_TEST_UNREADY="${2:-/nonexistent}" $BUSY
    wait_for 10 "pgrep -x BusyApp > /dev/null" || { print "BusyApp didn't launch"; return 1; }
    /bin/sleep 1
}

# Flick's USR1 dump: a "dump <app> pid <pid>: <n> windows" line per watched app, then "dump shown <rows>".
flick_dump() {
    local since=$(date "+%Y-%m-%d %H:%M:%S")
    pkill -USR1 -x Flick
    /bin/sleep 1
    /usr/bin/log show --start "$since" --style compact \
        --predicate 'subsystem == "com.zmievsa.flick" AND eventMessage BEGINSWITH "dump"' \
        | grep " dump " | sed 's/.* dump /dump /'
}

# Rows the Switcher would show right now, as "App: title" separated by " | ".
switcher_rows() {
    local line=$(flick_dump | grep "^dump shown" | tail -1)
    [[ -n "$line" ]] || return 1 # no dump came back
    print -r -- "${line#dump shown}"
}

# A freshly signed Flick takes a few seconds to start, so tests wait until it has picked up BusyApp.
wait_until_flick_watches_busy_app() {
    wait_for 60 'flick_dump | grep -q "^dump BusyApp pid"' || { print "Flick never started watching BusyApp"; return 1; }
}

fail() { print "FAIL $1"; FAILED=1; }

# Polls the Switcher's rows until one contains `row`, for up to `seconds`.
expect_row() { # test name, row, seconds
    local rows
    local deadline=$((SECONDS + $3))
    while true; do
        rows=$(switcher_rows)
        [[ "$rows" == *"$2"* ]] && { print "PASS $1"; return; }
        (( SECONDS >= deadline )) && break
        /bin/sleep 1
    done
    fail "$1: no row \"$2\" after $3 s in: $rows"
}

# Precondition: the row is missing, so a test can't pass because BusyApp showed its window to Flick anyway.
expect_no_row() { # test name, row
    local rows
    rows=$(switcher_rows) || { fail "$1: Flick returned no dump"; return 1; }
    [[ "$rows" != *"$2"* ]] || { fail "$1: precondition broken, \"$2\" was already listed"; return 1; }
}

test__switcher__when_app_hides_its_windows_while_flick_starts__should_list_them_once_it_shows_them() {
    local title="Unready app $RANDOM"
    touch $WORK/unready
    launch_busy_app "$title" $WORK/unready && start_flick && wait_until_flick_watches_busy_app || { fail $0; return; }
    expect_no_row $0 "BusyApp: $title" || return
    rm $WORK/unready
    expect_row $0 "BusyApp: $title" 20
}

test__switcher__when_app_is_frozen_longer_than_a_minute_while_flick_starts__should_list_its_window_once_it_answers() {
    local title="Frozen app $RANDOM"
    launch_busy_app "$title" || { fail $0; return; }
    kill -STOP $(pgrep -x BusyApp)
    start_flick || { fail $0; return; }
    /bin/sleep 65
    expect_no_row $0 "BusyApp: $title" || return
    kill -CONT $(pgrep -x BusyApp)
    expect_row $0 "BusyApp: $title" 20
}

make all > /dev/null || exit 1
build_busy_app > /dev/null 2>&1 || { print "Couldn't build BusyApp"; exit 1; }
# `Tests/run.sh test__a test__b` runs only those tests.
for test in ${@:-${(ok)functions[(I)test__*]}}; do $test; done
exit $FAILED
