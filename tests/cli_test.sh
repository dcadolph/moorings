#!/bin/sh
# cli_test drives the moorings command in a throwaway home folder. Run it from the repo root
# with: sh tests/cli_test.sh
set -u

repo="$(pwd -P)"
cli="$repo/moorings"
passes=0
failures=0
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# check records a failure named $1 unless the rest of the arguments run successfully.
check() {
	name="$1"
	shift
	if "$@"; then
		passes=$((passes + 1))
	else
		failures=$((failures + 1))
		echo "FAIL $name"
	fi
}

# fresh makes an empty home folder with a fake Applications folder and launchctl.
fresh() {
	HOME="$scratch/home$1"
	mkdir -p "$HOME/Apps"
	export HOME
	MOORINGS_APPS="$HOME/Apps"
	MOORINGS_LAUNCHCTL="$HOME/launchctl"
	export MOORINGS_APPS MOORINGS_LAUNCHCTL
	printf '#!/bin/sh\necho "$@" >>"%s/launchctl.log"\n' "$HOME" >"$MOORINGS_LAUNCHCTL"
	chmod +x "$MOORINGS_LAUNCHCTL"
}

# hammerspoon installs a fake Hammerspoon.app of version $1.
hammerspoon() {
	mkdir -p "$HOME/Apps/Hammerspoon.app/Contents"
	cat >"$HOME/Apps/Hammerspoon.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleShortVersionString</key>
	<string>$1</string>
</dict>
</plist>
EOF
}

# count prints how many lines of file $2 equal $1.
count() {
	grep -cxF -e "$1" "$2" || true
}

# has reports whether file $2 contains text $1.
has() {
	grep -qF -e "$1" "$2"
}

# Test 0: version prints the version from updates.lua, and an unknown command exits 2.
fresh 0
want="$(sed -n 's/^U\.version = "\(.*\)"$/\1/p' "$repo/updates.lua")"
check "t0 version" [ "$("$cli" version)" = "$want" ]
check "t0 version set" [ -n "$want" ]
"$cli" bogus >/dev/null 2>&1
check "t0 unknown" [ $? -eq 2 ]
"$cli" >/dev/null 2>&1
check "t0 none" [ $? -eq 2 ]

# Test 1: setup on a fresh home makes the folder, the link and an init.lua that loads moorings,
# and a second run changes nothing.
fresh 1
"$cli" setup >"$scratch/out1" 2>&1
check "t1 exit" [ $? -eq 0 ]
check "t1 link" [ "$(readlink "$HOME/.hammerspoon/moorings")" = "$repo" ]
check "t1 require" has 'moorings = require("anchors").start()' "$HOME/.hammerspoon/init.lua"
check "t1 path" has 'package.path = hs.configdir .. "/moorings/?.lua;" .. package.path' \
	"$HOME/.hammerspoon/init.lua"
before="$(cat "$HOME/.hammerspoon/init.lua")"
"$cli" setup >"$scratch/out1b" 2>&1
check "t1 again exit" [ $? -eq 0 ]
check "t1 again same" [ "$(cat "$HOME/.hammerspoon/init.lua")" = "$before" ]
check "t1 no backups" [ "$(find "$HOME/.hammerspoon" -name 'init.lua.moorings-backup-*' | wc -l)" -eq 0 ]
check "t1 again says" has "already loads moorings" "$scratch/out1b"

# Test 2: setup keeps an existing init.lua, backs it up first, and appends one block.
fresh 2
mkdir -p "$HOME/.hammerspoon"
printf 'hs.alert.show("mine")\n' >"$HOME/.hammerspoon/init.lua"
"$cli" setup >/dev/null 2>&1
check "t2 kept" has 'hs.alert.show("mine")' "$HOME/.hammerspoon/init.lua"
check "t2 one block" [ "$(count 'moorings = require("anchors").start()' "$HOME/.hammerspoon/init.lua")" -eq 1 ]
backup="$(find "$HOME/.hammerspoon" -name 'init.lua.moorings-backup-*')"
check "t2 backup" [ "$(cat "$backup")" = 'hs.alert.show("mine")' ]

# Test 3: setup refuses a link to somewhere else and a real folder, and changes neither.
fresh 3
mkdir -p "$HOME/.hammerspoon"
ln -s /somewhere/else "$HOME/.hammerspoon/moorings"
"$cli" setup >"$scratch/out3" 2>&1
check "t3 refused" [ $? -eq 1 ]
check "t3 link kept" [ "$(readlink "$HOME/.hammerspoon/moorings")" = "/somewhere/else" ]
check "t3 says" has "already links to /somewhere/else" "$scratch/out3"
check "t3 no init" [ ! -e "$HOME/.hammerspoon/init.lua" ]
rm "$HOME/.hammerspoon/moorings"
mkdir "$HOME/.hammerspoon/moorings"
"$cli" setup >/dev/null 2>&1
check "t3 folder refused" [ $? -eq 1 ]
check "t3 folder kept" test -d "$HOME/.hammerspoon/moorings" -a ! -L "$HOME/.hammerspoon/moorings"

# Test 4: doctor fails without Hammerspoon, without setup, and on an old Hammerspoon, and
# passes once everything is in place.
fresh 4
"$cli" doctor >"$scratch/out4" 2>&1
check "t4 bare fails" [ $? -eq 1 ]
check "t4 no app" has "FAIL  Hammerspoon is not installed" "$scratch/out4"
check "t4 no link" has "is missing. Run: moorings setup" "$scratch/out4"
check "t4 no init" has "does not load moorings" "$scratch/out4"
hammerspoon 1.0.0
"$cli" setup >/dev/null 2>&1
"$cli" doctor >"$scratch/out4b" 2>&1
check "t4 old fails" [ $? -eq 1 ]
check "t4 old says" has "FAIL  Hammerspoon 1.0.0 is older than" "$scratch/out4b"
hammerspoon 1.1.10
"$cli" doctor >"$scratch/out4c" 2>&1
check "t4 good" [ $? -eq 0 ]
check "t4 good says" has "ok    Hammerspoon 1.1.10" "$scratch/out4c"
check "t4 no fail lines" [ "$(grep -c '^FAIL' "$scratch/out4c")" -eq 0 ]
rm "$HOME/.hammerspoon/moorings"
"$cli" doctor >"$scratch/out4d" 2>&1
check "t4 link alone fails" [ $? -eq 1 ]
check "t4 link alone says" [ "$(grep -c '^FAIL' "$scratch/out4d")" -eq 1 ]

# Test 5: uninstall takes out exactly what setup put in, removes the keep-alive helper, and
# leaves the rest of init.lua.
fresh 5
mkdir -p "$HOME/.hammerspoon" "$HOME/Library/LaunchAgents"
printf 'hs.alert.show("mine")\n-- after\n' >"$HOME/.hammerspoon/init.lua"
"$cli" setup >/dev/null 2>&1
touch "$HOME/Library/LaunchAgents/moorings.keepalive.plist"
"$cli" uninstall >"$scratch/out5" 2>&1
check "t5 exit" [ $? -eq 0 ]
check "t5 link gone" test ! -e "$HOME/.hammerspoon/moorings" -a ! -L "$HOME/.hammerspoon/moorings"
printf 'hs.alert.show("mine")\n-- after\n' >"$scratch/want5"
check "t5 init restored" cmp -s "$scratch/want5" "$HOME/.hammerspoon/init.lua"
check "t5 agent gone" [ ! -e "$HOME/Library/LaunchAgents/moorings.keepalive.plist" ]
check "t5 bootout" has "bootout gui/$(id -u)/moorings.keepalive" "$HOME/launchctl.log"
"$cli" uninstall >/dev/null 2>&1
check "t5 twice" [ $? -eq 0 ]

# Test 6: uninstall leaves a link it did not make and lines it did not add.
fresh 6
mkdir -p "$HOME/.hammerspoon"
ln -s /my/own/clone "$HOME/.hammerspoon/moorings"
printf 'moorings = require("anchors").start()\n' >"$HOME/.hammerspoon/init.lua"
"$cli" uninstall >"$scratch/out6" 2>&1
check "t6 link kept" [ "$(readlink "$HOME/.hammerspoon/moorings")" = "/my/own/clone" ]
check "t6 init kept" [ "$(cat "$HOME/.hammerspoon/init.lua")" = 'moorings = require("anchors").start()' ]
check "t6 says" has "Delete them by hand" "$scratch/out6"
check "t6 link says" has "Left $HOME/.hammerspoon/moorings alone" "$scratch/out6"
check "t6 no launchctl" [ ! -e "$HOME/launchctl.log" ]

# Test 7: Installed the Homebrew way, the command finds its files through the bin link and
# setup links the opt path, so upgrades follow, and uninstall knows that link as its own.
fresh 7
prefix="$scratch/brew"
cellar="$prefix/Cellar/moorings/9.9.9"
mkdir -p "$cellar/bin" "$cellar/share/moorings" "$prefix/bin" "$prefix/opt"
cp "$repo"/*.lua "$cellar/share/moorings/"
cp "$cli" "$cellar/bin/moorings"
ln -s ../Cellar/moorings/9.9.9 "$prefix/opt/moorings"
ln -s ../Cellar/moorings/9.9.9/bin/moorings "$prefix/bin/moorings"
"$prefix/bin/moorings" setup >/dev/null 2>&1
check "t7 exit" [ $? -eq 0 ]
check "t7 opt link" [ "$(readlink "$HOME/.hammerspoon/moorings")" = "$(cd "$prefix" && pwd -P)/opt/moorings/share/moorings" ]
check "t7 version" [ "$("$prefix/bin/moorings" version)" = "$want" ]
"$prefix/bin/moorings" uninstall >/dev/null 2>&1
check "t7 uninstalled" [ ! -L "$HOME/.hammerspoon/moorings" ]

# Test 8: Without its files the command says so and exits 1.
fresh 8
mkdir -p "$scratch/lonely"
cp "$cli" "$scratch/lonely/moorings"
"$scratch/lonely/moorings" version >"$scratch/out8" 2>&1
check "t8 exit" [ $? -eq 1 ]
check "t8 says" has "cannot find the moorings files" "$scratch/out8"

# Test 9: selftest opens the run URL, reads the result Hammerspoon writes, prints each check
# and exits 0 only on a clean run, and --control exits 0 only when the planted check alone
# fails. It needs plutil, so it runs on macOS only.
if command -v plutil >/dev/null 2>&1; then
	fresh 9
	MOORINGS_LOGS="$HOME/logs"
	MOORINGS_OPEN="$HOME/open"
	MOORINGS_PGREP="$HOME/pgrep"
	MOORINGS_SELFTEST_SECONDS=2
	export MOORINGS_LOGS MOORINGS_OPEN MOORINGS_PGREP MOORINGS_SELFTEST_SECONDS
	mkdir -p "$MOORINGS_LOGS"
	# The fake pgrep reports the pid in $HOME/hs.pid as Hammerspoon's, and nothing without it.
	cat >"$MOORINGS_PGREP" <<'EOF'
#!/bin/sh
cat "$HOME/hs.pid" 2>/dev/null
EOF
	chmod +x "$MOORINGS_PGREP"
	echo 500 >"$HOME/hs.pid"
	# The fake open records the URL and answers with $HOME/answer.json as the run's result.
	cat >"$MOORINGS_OPEN" <<'EOF'
#!/bin/sh
echo "$@" >>"$HOME/open.log"
if [ -f "$HOME/crash" ]; then
	echo 501 >"$HOME/hs.pid"
fi
id="${2#*run=}"
id="${id%%&*}"
if [ -f "$HOME/answer.json" ]; then
	cp "$HOME/answer.json" "$MOORINGS_LOGS/selftest-$id.json"
fi
EOF
	chmod +x "$MOORINGS_OPEN"
	ok='{"name":"anchored window lands in its slot","ok":true,"detail":""}'
	skipped='{"name":"restart helper is loaded and current","ok":true,"skipped":true,"detail":"off"}'
	bad='{"name":"anchored window lands in its slot","ok":false,"detail":"at {40,25,512,1415}"}'
	other='{"name":"open picker is not held","ok":false,"detail":"anchored"}'
	planted='"planted":"anchored window lands in its slot"'

	printf '{"run":"x","pass":true,"checks":[%s,%s]}' "$ok" "$skipped" >"$HOME/answer.json"
	"$cli" selftest >"$scratch/out9" 2>&1
	check "t9 pass exit" [ $? -eq 0 ]
	check "t9 url" grep -Eq '^-g hammerspoon://moorings-selftest\?run=[0-9]{8}-[0-9]{6}-[0-9]+$' \
		"$HOME/open.log"
	check "t9 ok line" has "ok    anchored window lands in its slot" "$scratch/out9"
	check "t9 skip line" has "skip  restart helper is loaded and current: off" "$scratch/out9"
	check "t9 result path" has "Result: $MOORINGS_LOGS/selftest-" "$scratch/out9"

	printf '{"run":"x","pass":false,"checks":[%s,%s]}' "$bad" "$skipped" >"$HOME/answer.json"
	"$cli" selftest >"$scratch/out9b" 2>&1
	check "t9 fail exit" [ $? -eq 1 ]
	check "t9 fail line" has "FAIL  anchored window lands in its slot: at {40,25,512,1415}" \
		"$scratch/out9b"

	printf '{"run":"x","pass":false,"error":"TextEdit is open","checks":[]}' >"$HOME/answer.json"
	"$cli" selftest >"$scratch/out9c" 2>&1
	check "t9 stopped exit" [ $? -eq 1 ]
	check "t9 stopped line" has "FAIL  the run stopped: TextEdit is open" "$scratch/out9c"

	printf '{"run":"x","pass":false,%s,"checks":[%s,%s]}' "$planted" "$bad" "$skipped" \
		>"$HOME/answer.json"
	"$cli" selftest --control >"$scratch/out9d" 2>&1
	check "t9 control exit" [ $? -eq 0 ]
	check "t9 control url" [ "$(tail -n 1 "$HOME/open.log" | grep -c '&control=1$')" -eq 1 ]
	check "t9 control says" has "failed only the planted check" "$scratch/out9d"

	printf '{"run":"x","pass":true,%s,"checks":[%s]}' "$planted" "$ok" >"$HOME/answer.json"
	"$cli" selftest --control >"$scratch/out9e" 2>&1
	check "t9 control never failed" [ $? -eq 1 ]
	printf '{"run":"x","pass":false,%s,"checks":[%s,%s]}' "$planted" "$other" "$bad" \
		>"$HOME/answer.json"
	"$cli" selftest --control >"$scratch/out9f" 2>&1
	check "t9 control extra failure" [ $? -eq 1 ]
	check "t9 control says count" has "but 2 checks failed" "$scratch/out9f"
	printf '{"run":"x","pass":false,"checks":[%s]}' "$bad" >"$HOME/answer.json"
	"$cli" selftest --control >/dev/null 2>&1
	check "t9 control without planted" [ $? -eq 1 ]

	rm "$HOME/answer.json"
	"$cli" selftest >"$scratch/out9g" 2>&1
	check "t9 no answer exit" [ $? -eq 1 ]
	check "t9 no answer says" has "no result after 2 seconds" "$scratch/out9g"

	touch "$HOME/crash"
	"$cli" selftest >"$scratch/out9h" 2>&1
	check "t9 crash exit" [ $? -eq 1 ]
	check "t9 crash says" has "Hammerspoon quit during the run" "$scratch/out9h"
	check "t9 crash no wait" [ "$(grep -c 'no result after' "$scratch/out9h")" -eq 0 ]

	rm "$HOME/hs.pid" "$HOME/crash"
	lines="$(wc -l <"$HOME/open.log")"
	"$cli" selftest >"$scratch/out9i" 2>&1
	check "t9 not running exit" [ $? -eq 1 ]
	check "t9 not running says" has "Hammerspoon is not running" "$scratch/out9i"
	check "t9 not running sends nothing" [ "$(wc -l <"$HOME/open.log")" -eq "$lines" ]

	"$cli" selftest --bogus >/dev/null 2>&1
	check "t9 bad flag" [ $? -eq 2 ]
fi

echo "$passes checks passed, $failures failed"
[ "$failures" -eq 0 ]
