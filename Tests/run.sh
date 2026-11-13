#!/bin/zsh
# End-to-end tests: the real Fabaka build against BusyApp, a stand-in for an app that is still busy at login.
# Each test asserts what the Switcher would list, read through Fabaka's USR1 dump, without activating BusyApp.
# Run with `make test`. It stops the installed Fabaka for about two minutes and starts it again at the end.
set -u
cd "${0:A:h}/.."

FABAKA=build/Fabaka.app
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
<key>CFBundleIdentifier</key><string>com.zmievsa.fabaka.test.busyapp</string>
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
    pkill -x Fabaka
    rm -rf $WORK
    [[ -d /Applications/Fabaka.app ]] && open /Applications/Fabaka.app
}
trap cleanup EXIT

wait_for() { # seconds, shell condition
    local deadline=$((SECONDS + $1))
    until eval "$2"; do
        (( SECONDS >= deadline )) && return 1
        /bin/sleep 0.5
    done
}

start_fabaka() {
    pkill -x Fabaka
    wait_for 10 "! pgrep -x Fabaka > /dev/null" || { print "Old Fabaka didn't quit"; return 1; }
    open $FABAKA
    wait_for 10 "pgrep -x Fabaka > /dev/null" || { print "Fabaka didn't launch"; return 1; }
    # SIGUSR1 kills Fabaka until its first line of code ignores it, so give it time before any dump.
    /bin/sleep 2
}

# Launches BusyApp in the background, never activating it, and waits for it to start.
launch_busy_app() { # title [unready flag]
    pkill -x BusyApp
    open -n -g --env FABAKA_TEST_TITLE="$1" --env FABAKA_TEST_UNREADY="${2:-/nonexistent}" $BUSY
    wait_for 10 "pgrep -x BusyApp > /dev/null" || { print "BusyApp didn't launch"; return 1; }
    /bin/sleep 1
}

# Fabaka's USR1 dump: a "dump <app> pid <pid>: <n> windows" line per watched app, then "dump shown <rows>".
fabaka_dump() {
    local since=$(date "+%Y-%m-%d %H:%M:%S")
    pkill -USR1 -x Fabaka
    /bin/sleep 1
    /usr/bin/log show --start "$since" --style compact \
        --predicate 'subsystem == "com.zmievsa.fabaka" AND eventMessage BEGINSWITH "dump"' \
        | grep " dump " | sed 's/.* dump /dump /'
}

# Rows the Switcher would show right now, as "App: title" or "App (no windows)" separated by " | ".
switcher_rows() {
    local line=$(fabaka_dump | grep "^dump shown" | tail -1)
    [[ -n "$line" ]] || return 1 # no dump came back
    print -r -- "${line#dump shown}"
}

# A freshly signed Fabaka takes a few seconds to start, so tests wait until it has picked up BusyApp.
wait_until_fabaka_watches_busy_app() {
    wait_for 60 'fabaka_dump | grep -q "^dump BusyApp pid"' || { print "Fabaka never started watching BusyApp"; return 1; }
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

# Precondition: the row is missing, so a test can't pass because BusyApp showed its window to Fabaka anyway.
expect_no_row() { # test name, row
    local rows
    rows=$(switcher_rows) || { fail "$1: Fabaka returned no dump"; return 1; }
    [[ "$rows" != *"$2"* ]] || { fail "$1: precondition broken, \"$2\" was already listed"; return 1; }
}

test__switcher__when_app_hides_its_windows_while_fabaka_starts__should_list_them_once_it_shows_them() {
    local title="Unready app $RANDOM"
    touch $WORK/unready
    launch_busy_app "$title" $WORK/unready && start_fabaka && wait_until_fabaka_watches_busy_app || { fail $0; return; }
    expect_no_row $0 "BusyApp: $title" || return
    rm $WORK/unready
    expect_row $0 "BusyApp: $title" 20
}

test__switcher__when_app_has_no_windows__should_list_the_app_until_it_shows_one() {
    local title="Windowless app $RANDOM"
    touch $WORK/unready
    launch_busy_app "$title" $WORK/unready && start_fabaka && wait_until_fabaka_watches_busy_app || { fail $0; return; }
    expect_row $0 "BusyApp (no windows)" 10
    rm $WORK/unready
    expect_row $0 "BusyApp: $title" 20
    local rows=$(switcher_rows)
    [[ "$rows" != *"BusyApp (no windows)"* ]] && print "PASS $0 (app row gone)" || fail "$0: app row still listed in: $rows"
}

test__switcher__when_app_is_frozen_while_fabaka_starts__should_list_the_app_so_you_can_quit_it() {
    launch_busy_app "Frozen app $RANDOM" || { fail $0; return; }
    kill -STOP $(pgrep -x BusyApp)
    start_fabaka || { fail $0; return; }
    expect_row $0 "BusyApp (no windows)" 10
    kill -CONT $(pgrep -x BusyApp)
}

test__switcher__when_app_with_no_windows_is_resident__should_leave_it_out() {
    # Only this key is touched, and put back as it was: absent, or the user's own list.
    local saved=$(defaults read com.zmievsa.fabaka residentBundleIDs 2>/dev/null | tr -d ' ,()"' | grep . | tr '\n' ' ')
    defaults write com.zmievsa.fabaka residentBundleIDs -array com.zmievsa.fabaka.test.busyapp
    touch $WORK/unready
    launch_busy_app "Resident app $RANDOM" $WORK/unready && start_fabaka && wait_until_fabaka_watches_busy_app || { fail $0; }
    local rows=$(switcher_rows)
    if [[ -z "$saved" ]]; then
        defaults delete com.zmievsa.fabaka residentBundleIDs
    else
        defaults write com.zmievsa.fabaka residentBundleIDs -array $(echo $saved)
    fi
    [[ -n "$rows" && "$rows" != *"BusyApp (no windows)"* ]] && print "PASS $0" || fail "$0: resident listed in: $rows"
}

test__switcher__when_app_is_frozen_longer_than_a_minute_while_fabaka_starts__should_list_its_window_once_it_answers() {
    local title="Frozen app $RANDOM"
    launch_busy_app "$title" || { fail $0; return; }
    kill -STOP $(pgrep -x BusyApp)
    start_fabaka || { fail $0; return; }
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
