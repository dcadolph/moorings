#!/bin/sh
# Measure Moorings against Rectangle and Loop and fail unless Moorings meets the four targets.
#
# Usage: bench.sh
#
# Environment:
#   N     Actions per active phase (default 100).
#   IDLE  Seconds of the idle window (default 120).
#   ROUNDS  Active phases per app, interleaved by round (default 3).
#   MOORINGS_ACTIVE_BOUND  Multiple of Rectangle's per-action CPU that Moorings may use (default 1.0).
#
# Every bound is computed from Rectangle and Loop measured in the same run.
#
#   Memory  Moorings phys_footprint at most 1.5 times Rectangle's and at most Loop's, read with
#           footprint -p at the end of the run.
#   Idle    Moorings at most 0.03 s of CPU over the idle window with both rivals running beside it,
#           and zero "pass" lines (one per pass, at debug level) in the log stream of the Moorings
#           subsystem during that window. CPU is the ps cputime delta.
#   Active  Moorings CPU per action at most 1.0 times Rectangle's and at most Loop's, each the
#           median over ROUNDS active phases. Per action is the cputime delta over an app's own
#           active phase divided by N. Each phase sends N alternating left and right half actions to
#           one Probe window. A round runs Moorings, Rectangle and Loop in turn, so a slow minute
#           lands on every app rather than on one.
#   Paused  Moorings at most 1 ms of CPU per foreign move (0.10 s over 100 moves). It is the median
#           Moorings cputime delta during the Rectangle active phases, while Moorings is paused,
#           divided by N. The Loop phase figure is shown in the table only.
#
# The probe opens its window before the idle window and the bench waits out the 30 s in which
# Moorings reads every app for a launched app's first window, and each active phase starts 3 s after
# the probe comes forward, past the 2 s of passes that activation wakes, so every app's phase
# measures the same settled desk.
#
# Needs Moorings, Rectangle and Loop running from /Applications, Accessibility trusted for Moorings,
# and the probe registered by make probe. Exits 2 when one is missing, 1 on any FAIL, 0 when every threshold passes.
# Moorings is the only app paused or resumed, and it is resumed again on exit.
set -u

N=${N:-100}
IDLE=${IDLE:-120}
ROUNDS=${ROUNDS:-3}
BOUND=${MOORINGS_ACTIVE_BOUND:-1.0}
apps="Moorings Rectangle Loop"
subsystem="com.dcadolph.moorings"
probe="com.dcadolph.moorings.probe"
tmp=$(mktemp -d)
paused=0
streampid=""

# pid prints the first pid of the named app's binary under /Applications.
pid() { pgrep -f "/Applications/$1.app/Contents/MacOS/$1" | head -1; }

# cpu prints the cumulative CPU seconds of a pid.
cpu() { ps -o time= -p "$1" | awk -F'[:.]' '{ printf "%.2f", $1*60 + $2 + $3/100 }'; }

# mem prints phys_footprint of a pid in the unit footprint reports.
mem() { footprint -p "$1" 2>/dev/null | awk '/phys_footprint:/ { print $2 $3 }' | head -1; }

# peak prints phys_footprint_peak of a pid in the unit footprint reports.
peak() { footprint -p "$1" 2>/dev/null | awk '/phys_footprint_peak:/ { print $2 $3 }' | head -1; }

# megabytes converts a footprint figure such as 20MB or 512KB to megabytes.
megabytes() {
	echo "$1" | awk '{
		v = $0 + 0
		if ($0 ~ /[Gg][Bb]/) v *= 1024
		else if ($0 ~ /[Kk][Bb]/) v /= 1024
		else if ($0 ~ /[Bb]$/ && $0 !~ /[Mm][Bb]/) v /= 1048576
		printf "%.2f", v
	}'
}

# median prints the middle of its numeric arguments, the lower middle for an even count.
median() { printf '%s\n' "$@" | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'; }

# phases prints the stored deltas of one app over every round of a phase, divided by N.
phases() {
	r=1
	while [ "$r" -le "$ROUNDS" ]; do
		eval "echo \$D_active_${1}_${r}_$2 $N" | awk '{ printf "%.4f\n", $1 / $2 }'
		r=$((r + 1))
	done
}

# pidof_app prints the pid recorded for an app.
pidof_app() { eval "echo \$P_$1"; }

# snap records the current CPU seconds of each app as the baseline.
snap() {
	for a in $apps; do
		eval "C0_$a=\$(cpu \$P_$a)"
	done
}

# delta prints the CPU seconds an app used since the last snap.
delta() {
	eval "base=\$C0_$1"
	now=$(cpu "$(pidof_app "$1")")
	echo "$now $base" | awk '{ printf "%.2f", $1 - $2 }'
}

# report prints one table line per app and stores the deltas as D_<label>_<app>, with every
# character of the label that cannot sit in a variable name turned into an underscore.
report() {
	label=$1
	secs=$2
	key=$(echo "$label" | tr -c 'A-Za-z0-9_\n' '_')
	for a in $apps; do
		d=$(delta "$a")
		eval "D_${key}_$a=$d"
		p=$(pidof_app "$a")
		printf "%-16s %-10s cpu %6.2f s over %4s s (%5.2f%%)  mem %s  peak %s\n" "$label" "$a" "$d" \
			"$secs" "$(echo "$d $secs" | awk '{ printf "%.4f", $1 * 100 / $2 }')" "$(mem "$p")" "$(peak "$p")"
	done
}

# pause clicks the Moorings menu item whose name starts with the given word, Pause or Resume.
pause() {
	if ! osascript -e "tell application \"System Events\" to tell process \"Moorings\"
		click menu bar item 1 of menu bar 1
		delay 0.6
		click (first menu item of menu 1 of menu bar item 1 of menu bar 1 whose name starts with \"⚓ $1\")
	end tell" >/dev/null 2>&1; then
		echo "bench: could not click the \"$1\" menu item of Moorings" >&2
		exit 2
	fi
}

# cleanup stops the debug stream, resumes Moorings if it is paused and removes scratch files.
cleanup() {
	if [ -n "$streampid" ]; then
		kill "$streampid" 2>/dev/null
		streampid=""
	fi
	if [ "$paused" = 1 ]; then
		paused=0
		pause Resume
	fi
	rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# run sends N alternating actions to the probe through one app's links and reports the phase as
# round $4.
run() {
	who=$1
	l=$2
	r=$3
	round=$4
	open -b "$probe"
	sleep 3
	snap
	t0=$(date +%s)
	i=1
	while [ "$i" -le "$N" ]; do
		if [ $((i % 2)) -eq 1 ]; then open -g "$l"; else open -g "$r"; fi
		sleep 0.25
		i=$((i + 1))
	done
	sleep 2
	report "active:$who:$round" $(($(date +%s) - t0))
}

# check prints a verdict line and records a failure.
fails=0
check() {
	name=$1
	ok=$2
	detail=$3
	if [ "$ok" = 1 ]; then
		printf "%-8s PASS  %s\n" "$name" "$detail"
	else
		printf "%-8s FAIL  %s\n" "$name" "$detail"
		fails=$((fails + 1))
	fi
}

missing=""
for a in $apps; do
	p=$(pid "$a")
	[ -n "$p" ] || missing="$missing $a"
	eval "P_$a=\$p"
done
if [ -n "$missing" ]; then
	echo "bench: no running process for:$missing" >&2
	exit 2
fi
if [ ! -d "$(dirname "$0")/../.build/MooringsProbe.app" ]; then
	echo "bench: no probe, run make probe in mac/" >&2
	exit 2
fi
open -g moorings://status
sleep 2
if ! /usr/bin/log show --last 10s --predicate "subsystem == \"$subsystem\"" 2>/dev/null |
	grep -q 'trusted=true'; then
	echo "bench: Moorings does not report trusted=true, Accessibility is not granted" >&2
	exit 2
fi

osascript -e "tell application id \"$probe\" to quit" >/dev/null 2>&1
sleep 1
open -b "$probe"
sleep 35
echo "idle ${IDLE}s, all three running, Moorings holding the layout"
/usr/bin/log stream --level debug \
	--predicate "subsystem == \"$subsystem\" AND eventMessage BEGINSWITH \"pass \"" \
	>"$tmp/stream.log" 2>/dev/null &
streampid=$!
sleep 2
snap
sleep "$IDLE"
kill "$streampid" 2>/dev/null
streampid=""
passes=$(grep -c '^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' "$tmp/stream.log")
report idle "$IDLE"
echo "idle             Moorings   debug-stream pass lines $passes"

round=1
while [ "$round" -le "$ROUNDS" ]; do
	run Moorings "moorings://action?name=left-half" "moorings://action?name=right-half" "$round"
	pause Pause
	paused=1
	sleep 1
	run Rectangle "rectangle://execute-action?name=left-half" "rectangle://execute-action?name=right-half" "$round"
	run Loop "loop://direction/leftHalf" "loop://direction/rightHalf" "$round"
	pause Resume
	paused=0
	round=$((round + 1))
done
osascript -e "tell application id \"$probe\" to quit" >/dev/null

mem_m=$(megabytes "$(mem "$P_Moorings")")
mem_r=$(megabytes "$(mem "$P_Rectangle")")
mem_l=$(megabytes "$(mem "$P_Loop")")
all_m=$(phases Moorings Moorings | tr '\n' ' ')
all_r=$(phases Rectangle Rectangle | tr '\n' ' ')
all_l=$(phases Loop Loop | tr '\n' ' ')
act_m=$(median $all_m)
act_r=$(median $all_r)
act_l=$(median $all_l)
pau_m=$(median $(phases Rectangle Moorings))
pau_l=$(median $(phases Loop Moorings))

echo
echo "active           per action over $ROUNDS rounds: Moorings ${all_m}s, Rectangle ${all_r}s, Loop ${all_l}s"
echo "paused           Moorings   median cpu per foreign move: Rectangle phases $pau_m s, Loop phases $pau_l s"
echo
echo "verdict"
ok=$(echo "$mem_m $mem_r $mem_l" | awk '{ print ($1 <= 1.5 * $2 && $1 <= $3) ? 1 : 0 }')
check Memory "$ok" "measured ${mem_m}MB, bound min(1.5 x Rectangle ${mem_r}MB, Loop ${mem_l}MB)"
ok=$(echo "$D_idle_Moorings $passes" | awk '{ print ($1 <= 0.03 && $2 == 0) ? 1 : 0 }')
check Idle "$ok" "measured ${D_idle_Moorings} s and $passes pass lines, bound 0.03 s and 0 pass lines"
ok=$(echo "$act_m $act_r $act_l $BOUND" | awk '{ print ($1 <= $4 * $2 && $1 <= $3) ? 1 : 0 }')
check Active "$ok" "median ${act_m} s per action, bound min(${BOUND} x Rectangle ${act_r}, Loop ${act_l})"
ok=$(echo "$pau_m" | awk '{ print ($1 <= 0.001) ? 1 : 0 }')
check Paused "$ok" "measured ${pau_m} s per foreign move, bound 0.001 s"

[ "$fails" -eq 0 ] || exit 1
exit 0
