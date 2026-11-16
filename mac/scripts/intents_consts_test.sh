#!/bin/sh
# Run intents_consts.sh against stub build trees and check its exit codes and the files it prints.
#
# Usage: intents_consts_test.sh
#
# Each case lays out empty const values files with set times under a scratch build folder, beside one
# app source dated 2026-11-09, so no compiler runs. A case that sets rebuild passes it as the rebuild
# command, and regen stands in for the build: it writes a missing file fresh and leaves an existing one
# alone.
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
failed=0
rebuild=""
regen=$root/regen.sh
cat >"$regen" <<'EOF'
#!/bin/sh
for file; do [ -e "$file" ] || touch -t 202611120000 "$file"; done
EOF
chmod +x "$regen"

fresh=202611120000
stale=202610290000
native=arm64-apple-macosx/release
universal=apple/Intermediates.noindex/Moorings.build/Release
swiftbuild=out/Intermediates.noindex/Moorings.build/Release
core=out/Intermediates.noindex/MooringsCore.build/Release
primary=Moorings-primary.swiftconstvalues
probe=MooringsProbe-primary.swiftconstvalues
arm=Objects-normal/arm64
intel=Objects-normal/x86_64

# put starts the case $1 if it is new, then writes an empty file at $3 under its build folder with
# the time $2.
put() {
	mkdir -p "$root/$1/Sources/Moorings/App" "$(dirname "$root/$1/.build/$3")"
	touch -t 202611090548 "$root/$1/Sources/Moorings/App/AppDelegate.swift"
	touch -t "$2" "$root/$1/.build/$3"
}

# expect runs the script on the case $1 with the bin path $2 and the architecture $3, and checks the
# files it prints, the exit code, and its stderr. A pattern starting with ! must not match.
#
# Arguments: name, bin path and files printed, both relative to the build folder, with the files as
# one string, wanted exit code, then stderr line patterns.
expect() {
	name=$1
	build=$root/$1/.build
	want=$(for file in $4; do echo "$build/$file"; done | sort)
	code=$5
	# shellcheck disable=SC2086 # The rebuild command splits into its words.
	got=$("$here/intents_consts.sh" "$build/$2" "$3" Moorings "$root/$1/Sources/Moorings" \
		${rebuild:+-- $rebuild} 2>"$root/$1/err")
	gotcode=$?
	rebuild=""
	shift 5
	bad=""
	[ "$gotcode" = "$code" ] || bad="exit $gotcode, want $code"
	[ "$got" = "$want" ] || bad="${bad:+$bad; }printed [$got], want [$want]"
	for pattern in "$@"; do
		case $pattern in
		!*)
			if grep -Eq -- "${pattern#!}" "$root/$name/err"; then
				bad="${bad:+$bad; }has: ${pattern#!}"
			fi
			;;
		*)
			if ! grep -Eq -- "$pattern" "$root/$name/err"; then
				bad="${bad:+$bad; }lacks: $pattern"
			fi
			;;
		esac
	done
	if [ -n "$bad" ]; then
		echo "FAIL $name: $bad"
		sed 's/^/    /' "$root/$name/err"
		failed=$((failed + 1))
	else
		echo "ok   $name"
	fi
}

put native $fresh $native/Moorings.build/Moorings.swiftconstvalues
put native $fresh $native/MooringsProbe.build/MooringsProbe.swiftconstvalues
put native $fresh $native/MooringsCore.build/MooringsCore.swiftconstvalues
expect native $native arm64 "$native/Moorings.build/Moorings.swiftconstvalues" 0

put native-per-source $fresh $native/Moorings.build/AppDelegate.swiftconstvalues
put native-per-source $fresh $native/Moorings.build/Intents.swiftconstvalues
expect native-per-source $native arm64 \
	"$native/Moorings.build/AppDelegate.swiftconstvalues $native/Moorings.build/Intents.swiftconstvalues" 0

put universal $fresh $universal/Moorings.build/$arm/$primary
put universal $fresh $universal/Moorings.build/$intel/$primary
put universal $fresh $universal/MooringsProbe.build/$arm/$probe
put universal $fresh $universal/MooringsCore_Module.build/$arm/MooringsCore_Module-primary.swiftconstvalues
expect universal apple/Products/Release arm64 "$universal/Moorings.build/$arm/$primary" 0

put swiftbuild-beside-stale-native $fresh $swiftbuild/Moorings-p.build/$arm/$primary
put swiftbuild-beside-stale-native $fresh $swiftbuild/MooringsProbe-p.build/$arm/$probe
put swiftbuild-beside-stale-native $fresh \
	$core/MooringsCore-t.build/$arm/MooringsCore-primary.swiftconstvalues
put swiftbuild-beside-stale-native $stale $native/Moorings.build/Moorings.swiftconstvalues
expect swiftbuild-beside-stale-native out/Products/Release arm64 \
	"$swiftbuild/Moorings-p.build/$arm/$primary" 0

put stale-alone $stale $swiftbuild/Moorings-p.build/$arm/$primary
expect stale-alone out/Products/Release arm64 "" 1 "stale const values" "Moorings-p.build/.*/$primary"

put stale-among-fresh $fresh $native/Moorings.build/AppDelegate.swiftconstvalues
put stale-among-fresh $stale $native/Moorings.build/Intents.swiftconstvalues
expect stale-among-fresh $native arm64 "" 1 "stale const values" "Intents.swiftconstvalues" \
	"!AppDelegate.swiftconstvalues"

put other-layout-only $fresh $native/Moorings.build/Moorings.swiftconstvalues
expect other-layout-only out/Products/Release arm64 "" 1 "no const values for Moorings \(arm64\)" \
	"$native/Moorings.build/Moorings.swiftconstvalues"

put probe-alone $fresh $swiftbuild/MooringsProbe-p.build/$arm/$probe
expect probe-alone out/Products/Release arm64 "" 1 "no const values for Moorings \(arm64\)"

put other-arch-alone $fresh $universal/Moorings.build/$intel/$primary
expect other-arch-alone apple/Products/Release arm64 "" 1 "no const values for Moorings \(arm64\)"

put stale-rebuilt $stale $swiftbuild/Moorings-p.build/$arm/$primary
rebuild="$regen $root/stale-rebuilt/.build/$swiftbuild/Moorings-p.build/$arm/$primary"
expect stale-rebuilt out/Products/Release arm64 "$swiftbuild/Moorings-p.build/$arm/$primary" 0 \
	"building them again" "!stale const values,"

put stale-among-fresh-rebuilt $fresh $native/Moorings.build/AppDelegate.swiftconstvalues
put stale-among-fresh-rebuilt $stale $native/Moorings.build/Intents.swiftconstvalues
rebuild="$regen $root/stale-among-fresh-rebuilt/.build/$native/Moorings.build/Intents.swiftconstvalues"
expect stale-among-fresh-rebuilt $native arm64 \
	"$native/Moorings.build/AppDelegate.swiftconstvalues $native/Moorings.build/Intents.swiftconstvalues" 0 \
	"Intents.swiftconstvalues" "!AppDelegate.swiftconstvalues"

put stale-rebuild-writes-nothing $stale $swiftbuild/Moorings-p.build/$arm/$primary
rebuild=true
expect stale-rebuild-writes-nothing out/Products/Release arm64 "" 1 "building them again" \
	"no const values for Moorings \(arm64\)"

put stale-rebuild-fails $stale $swiftbuild/Moorings-p.build/$arm/$primary
rebuild=false
expect stale-rebuild-fails out/Products/Release arm64 "" 1 "rebuild failed: false"

put fresh-rebuild-unused $fresh $swiftbuild/Moorings-p.build/$arm/$primary
rebuild=false
expect fresh-rebuild-unused out/Products/Release arm64 "$swiftbuild/Moorings-p.build/$arm/$primary" 0 \
	"!building them again"

if [ "$failed" -gt 0 ]; then
	echo "$failed failed"
	exit 1
fi
echo "all passed"
