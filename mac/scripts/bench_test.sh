#!/bin/sh
# Run bench.sh and use.sh against stub apps and check their exit codes and verdicts.
#
# Usage: bench_test.sh
#
# Each case copies the scripts to a scratch tree beside a stub probe, and puts stubs for open,
# osascript, pgrep, footprint, log and sleep first on PATH, so no window moves and no time passes.
# Moorings, Rectangle and Loop start as pids 100, 200 and 300, and each stub records its effects in
# the case's state directory.
set -u

here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
failed=0

# stubs writes the stub commands and the stub probe under the tree $1.
stubs() {
	mkdir -p "$1/bin" "$1/mac/scripts" "$1/mac/.build/MooringsProbe.app/Contents/MacOS"

	cat >"$1/bin/open" <<'EOF'
#!/bin/sh
for arg in "$@"; do
	case $arg in
	moorings://action*)
		echo $(($(cat "$STATE/trips") + ${ACTION_TRIPS:-11})) >"$STATE/trips"
		n=$(($(cat "$STATE/actions") + 1))
		echo "$n" >"$STATE/actions"
		if [ "$n" = "${MOORINGS_DIES_AT:-0}" ]; then
			: >"$STATE/pid_Moorings"
		fi
		;;
	loop://*)
		n=$(($(cat "$STATE/loops") + 1))
		echo "$n" >"$STATE/loops"
		if [ "$n" = "${LOOP_CRASHES_AT:-0}" ]; then
			"$STUBS/crash" "${LOOP_STAYS_DOWN:-}"
		fi
		;;
	/Applications/Loop.app)
		echo 302 >"$STATE/pid_Loop"
		;;
	esac
done
exit 0
EOF

	cat >"$1/bin/crash" <<'EOF'
#!/bin/sh
cat "$STATE/pid_Loop" >>"$STATE/dead"
if [ -n "$1" ]; then
	: >"$STATE/pid_Loop"
else
	echo 301 >"$STATE/pid_Loop"
fi
EOF

	cat >"$1/bin/pgrep" <<'EOF'
#!/bin/sh
for arg in "$@"; do
	case $arg in
	*/Moorings) cat "$STATE/pid_Moorings" ;;
	*/Rectangle) cat "$STATE/pid_Rectangle" ;;
	*/Loop) cat "$STATE/pid_Loop" ;;
	esac
done
EOF

	cat >"$1/bin/footprint" <<'EOF'
#!/bin/sh
grep -qx "$2" "$STATE/dead" && exit 1
case $2 in
1*) mb=20 ;;
2*) mb=20 ;;
3*) mb=40 ;;
esac
echo "phys_footprint: $mb MB"
echo "phys_footprint_peak: $mb MB"
EOF

	cat >"$1/bin/log" <<'EOF'
#!/bin/sh
case $1 in
show)
	echo $(($(cat "$STATE/trips") + 7)) >"$STATE/trips"
	echo "status: trusted=true trips=$(cat "$STATE/trips")"
	;;
stream)
	exec /bin/sleep 600
	;;
esac
EOF

	printf '#!/bin/sh\nexit 0\n' >"$1/bin/osascript"
	printf '#!/bin/sh\nexit 0\n' >"$1/bin/sleep"

	# The stub CPU reading grows by a rate per pid at each read, so Moorings stays under both rivals.
	cat >"$1/mac/.build/MooringsProbe.app/Contents/MacOS/MooringsProbe" <<'EOF'
#!/bin/sh
case $1 in
--cpu)
	if grep -qx "$2" "$STATE/dead"; then
		echo "probe: cannot read the CPU time of pid $2" >&2
		exit 1
	fi
	n=$(($(cat "$STATE/reads") + 1))
	echo "$n" >"$STATE/reads"
	case $2 in
	1*) rate=1 ;;
	2*) rate=2 ;;
	3*) rate=${LOOP_RATE:-3} ;;
	esac
	echo "$n $rate" | awk '{ printf "%.6f\n", $1 * $2 / 1000 }'
	;;
--latency)
	case $3 in
	moorings*) echo "p50 10.0 p95 11.0 missed 0 wrong 0 n $2" ;;
	rectangle*) echo "p50 20.0 p95 21.0 missed 0 wrong 0 n $2" ;;
	loop*) echo "p50 30.0 p95 31.0 missed 0 wrong 0 n $2" ;;
	esac
	;;
--walk)
	n=$(($(cat "$STATE/walks") + 1))
	echo "$n" >"$STATE/walks"
	if [ "$n" = "${LOOP_CRASHES_IN_WALK:-0}" ]; then
		"$STUBS/crash"
	fi
	echo $(($(cat "$STATE/trips") + ${WALK_TRIPS:-0})) >"$STATE/trips"
	echo "walk seconds $2"
	;;
--drags)
	echo "error not trusted"
	;;
esac
EOF

	chmod +x "$1"/bin/* "$1/mac/.build/MooringsProbe.app/Contents/MacOS/MooringsProbe"
}

# expect runs one script of the tree $3 as case $1 with the env assignments that follow and checks
# its exit code and that its output holds or lacks each line pattern. A pattern starting with ! must
# not match.
#
# Arguments: name, script, tree, wanted exit code, assignments as one string, then patterns.
expect() {
	name=$1
	script=$2
	tree=$3
	want=$4
	assigns=$5
	shift 5
	state="$tree/state/$name"
	mkdir -p "$state"
	echo 100 >"$state/pid_Moorings"
	echo 200 >"$state/pid_Rectangle"
	echo 300 >"$state/pid_Loop"
	: >"$state/dead"
	for f in trips actions loops reads walks; do
		echo 0 >"$state/$f"
	done
	# shellcheck disable=SC2086
	got=$(env STATE="$state" STUBS="$tree/bin" PATH="$tree/bin:$PATH" N=4 IDLE=1 ROUNDS=3 LAT=2 WALK=1 $assigns \
		"$tree/mac/scripts/$script" 2>&1)
	code=$?
	bad=""
	[ "$code" = "$want" ] || bad="exit $code, want $want"
	for pattern in "$@"; do
		case $pattern in
		!*)
			if printf '%s\n' "$got" | grep -Eq -- "${pattern#!}"; then
				bad="$bad; has: ${pattern#!}"
			fi
			;;
		*)
			if ! printf '%s\n' "$got" | grep -Eq -- "$pattern"; then
				bad="$bad; lacks: $pattern"
			fi
			;;
		esac
	done
	if [ -n "$bad" ]; then
		echo "FAIL $name: $bad"
		printf '%s\n' "$got" | tail -12 | sed 's/^/    /'
		failed=$((failed + 1))
	else
		echo "ok   $name"
	fi
}

tree="$root/tree"
stubs "$tree"
cp "$here/bench.sh" "$here/use.sh" "$here/measure.sh" "$tree/mac/scripts/"
sed -i '' 's|/usr/bin/log|log|g' "$tree/mac/scripts/bench.sh" "$tree/mac/scripts/use.sh" "$tree/mac/scripts/measure.sh"

expect bench-steady bench.sh "$tree" 0 "" \
	"^Trips +PASS +per action 11.00, bound 12" "^Memory +PASS" "^Active +PASS" "!restarted" "!cannot read"
expect bench-trips-over-the-bound bench.sh "$tree" 1 "ACTION_TRIPS=13" \
	"^Trips +FAIL +per action 13.00, bound 12"
expect bench-trips-bound-from-env bench.sh "$tree" 1 "MOORINGS_TRIPS_BOUND=0.5" \
	"^Trips +FAIL +per action 11.00, bound 0.5"
expect bench-loop-crashes-and-returns bench.sh "$tree" 0 "LOOP_CRASHES_AT=2" \
	"^Loop restarted: pid 300 is now 301" "^Memory +PASS.*Loop 40.00MB" "^Active +PASS" \
	"active:Loop:2 +Loop +cpu +0\.00[1-9]"
expect bench-loop-crashes-and-stays-down bench.sh "$tree" 0 "LOOP_CRASHES_AT=2 LOOP_STAYS_DOWN=1" \
	"^Loop restarted: pid 300 is now 302" "^Memory +PASS.*Loop 40.00MB" "^Active +PASS"
expect bench-moorings-dies bench.sh "$tree" 2 "MOORINGS_DIES_AT=2" \
	"Moorings pid 100 is gone" "!^verdict"
expect use-steady use.sh "$tree" 0 "DRAGS=0" "^Use +PASS" "^Paused +PASS +measured 0 net" "!restarted"
expect use-moorings-over-loop use.sh "$tree" 0 "DRAGS=0 LOOP_RATE=0" "^Use +PASS.*Loop 0.0000 s for information"
expect use-over-the-baseline use.sh "$tree" 1 "DRAGS=0 MOORINGS_USE_BASELINE=0.0001" "^Use +FAIL"
expect use-paused-at-the-bound use.sh "$tree" 0 "DRAGS=0 WALK_TRIPS=630" "^Paused +PASS +measured 630 net round trips, bound 630"
expect use-paused-over-the-bound use.sh "$tree" 1 "DRAGS=0 WALK_TRIPS=631" "^Paused +FAIL +measured 631 net"
expect use-loop-crashes-in-a-walk use.sh "$tree" 0 "DRAGS=0 LOOP_CRASHES_IN_WALK=2" \
	"^Loop restarted: pid 300 is now 301" "^use round 2:.*Loop 0\.0000 s" "^use round 3:.*Loop 0\.0[0-9]" "^Use +PASS"

if [ "$failed" -gt 0 ]; then
	echo "$failed failed"
	exit 1
fi
echo "all passed"
