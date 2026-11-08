#!/bin/sh
# Measure Moorings against Rectangle and Loop and fail unless Moorings meets the four targets.
#
# Usage: bench.sh
#
# Release bench: ROUNDS=5 make bench
#
# Environment:
#   N     Actions per active phase (default 100).
#   IDLE  Seconds of the idle window (default 120).
#   ROUNDS  Active phases per app, interleaved by round (default 3).
#   LAT   Actions per latency run (default 20).
#   MOORINGS_ACTIVE_BOUND  Multiple of Rectangle's per-action CPU that Moorings may use (default 1.0).
#   MOORINGS_TRIPS_BOUND   Round trips per action that Moorings may make (default TRIPS below).
#
# Every bound but Trips is computed from Rectangle and Loop measured in the same run.
#
#   Memory  Moorings phys_footprint at most 1.5 times Rectangle's and at most Loop's, read with
#           footprint -p at the end of the run.
#   Idle    Moorings at most 0.03 s of CPU over the idle window with both rivals running beside it,
#           and zero "pass" lines (one per pass, at debug level) in the log stream of the Moorings
#           subsystem during that window. CPU is the delta of the user plus system time the probe
#           reads in microseconds with proc_pid_rusage.
#   Active  Moorings CPU per action at most 1.0 times Rectangle's and at most Loop's, each the
#           median over ROUNDS active phases. Per action is the CPU time delta, read in
#           microseconds, over an app's own active phase divided by N. Each phase sends N
#           alternating left and right half actions to one Probe window. A round runs Moorings, Rectangle and Loop in turn, so a slow minute
#           lands on every app rather than on one.
#   Paused  Moorings at most 1 ms of CPU per foreign move (0.10 s over 100 moves). It is the median
#           Moorings CPU time delta, read in microseconds, during the Rectangle active phases, while
#           Moorings is paused, divided by N. The Loop phase figure is shown in the table only.
#   Latency Moorings landed p95 at most Rectangle's p95 and at most Loop's p50, each the median
#           over ROUNDS latency runs, with no action missed or landed on the wrong side. A latency
#           run follows each app's active phase, outside its CPU window: the running probe opens
#           LAT alternating left and right links without bringing the app forward and times each
#           from the open to the window's last move before it holds still for 0.3 s. An action
#           that moves nothing within 2 s is missed.
#   Lat50   Moorings landed p50 at most Rectangle's p50 and at most Loop's p50, medians as above.
#   Trips   Moorings Accessibility round trips per action at most TRIPS. A trips phase after the
#           rounds, outside every CPU window, sends N alternating actions to the probe with the
#           scan log streamed at debug level. Per action is the status line's trips= delta over the
#           phase, less one status request's own trips (measured by two status reads in a row)
#           and less the sum of the scans the log shows, divided by N, so it counts the action
#           path alone and not the timed full pass that the actions keep awake.
#
# The probe opens its window before the idle window and the bench waits out the 30 s in which
# Moorings reads every app for a launched app's first window, and each active phase starts 3 s after
# the probe comes forward, past the 2 s of passes that activation wakes, so every app's phase
# measures the same settled desk.
#
# Needs Moorings, Rectangle and Loop running from /Applications, Accessibility trusted for Moorings,
# and the probe registered by make probe. Exits 2 when one is missing, 1 on any FAIL, 0 when every threshold passes.
# Moorings is the only app paused or resumed, and it is resumed again on exit. A rival that crashes
# is followed to its new pid at the next phase, and the phase it crashed in counts as 0.
set -u

# TRIPS is the round trips per action bound, the 11.48 that two runs on v1.18.1 measured alike
# rounded up to a whole number. It only ever goes down.
TRIPS=12

N=${N:-100}
IDLE=${IDLE:-120}
ROUNDS=${ROUNDS:-3}
LAT=${LAT:-20}
BOUND=${MOORINGS_ACTIVE_BOUND:-1.0}
TRIPS_BOUND=${MOORINGS_TRIPS_BOUND:-$TRIPS}
apps="Moorings Rectangle Loop"
subsystem="com.dcadolph.moorings"
probe="com.dcadolph.moorings.probe"
tmp=$(mktemp -d)
paused=0
streampid=""

. "$(dirname "$0")/measure.sh"

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

# snap refreshes the pids and records the current CPU seconds of each app as the baseline.
snap() {
	repid
	for a in $apps; do
		eval "C0_$a=\$(cpu \$P_$a)"
	done
}

# delta prints the CPU seconds an app used since the last snap.
delta() {
	eval "base=\$C0_$1"
	spent "$(pidof_app "$1")" "$base"
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
		printf "%-16s %-10s cpu %8.4f s over %4s s (%5.2f%%)  mem %s  peak %s\n" "$label" "$a" "$d" \
			"$secs" "$(echo "$d $secs" | awk '{ printf "%.4f", $1 * 100 / $2 }')" "$(mem "$p")" "$(peak "$p")"
	done
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

# latency asks the running probe to time LAT alternating actions through one app's links and
# stores round $4's p50, p95, missed and wrong counts as L50_, L95_, LM_ and LW_<app>_<round>.
latency() {
	who=$1
	l=$2
	r=$3
	round=$4
	if ! line=$(probebin --latency "$LAT" "$l" "$r"); then
		echo "bench: the probe sent no latency line for $who" >&2
		exit 2
	fi
	echo "latency $who round $round: $line"
	case $line in
	"p50 "*) ;;
	*)
		echo "bench: the probe refused the latency run for $who" >&2
		exit 2
		;;
	esac
	set -- $line
	eval "L50_${who}_$round=$2 L95_${who}_$round=$4 LM_${who}_$round=$6 LW_${who}_$round=$8"
}

# tripsphase sends N alternating Moorings actions to the probe with the scan log streamed and sets
# TR_per to the round trips per action net of one status request and of the scans.
tripsphase() {
	open -b "$probe"
	sleep 3
	ta=$(trips)
	tb=$(trips)
	pred="subsystem == \"$subsystem\" AND category == \"windows\""
	/usr/bin/log stream --level debug --predicate "$pred AND eventMessage BEGINSWITH \"scan \"" \
		>"$tmp/scans.log" 2>/dev/null &
	streampid=$!
	sleep 2
	tc=$(trips)
	i=1
	while [ "$i" -le "$N" ]; do
		if [ $((i % 2)) -eq 1 ]; then
			open -g "moorings://action?name=left-half"
		else
			open -g "moorings://action?name=right-half"
		fi
		sleep 0.25
		i=$((i + 1))
	done
	sleep 2
	td=$(trips)
	sleep 1
	kill "$streampid" 2>/dev/null
	streampid=""
	if [ -z "$ta" ] || [ -z "$tb" ] || [ -z "$tc" ] || [ -z "$td" ]; then
		echo "bench: Moorings sent no trips= status line" >&2
		exit 2
	fi
	scans=$(grep -c 'scan .* trips [0-9]' "$tmp/scans.log")
	scansum=$(grep -o 'trips [0-9]*' "$tmp/scans.log" | awk '{ s += $2 } END { print s + 0 }')
	status=$((tb - ta))
	TR_per=$(echo "$td $tc $status $scansum $N" | awk '{ printf "%.2f", ($1 - $2 - $3 - $4) / $5 }')
	echo "trips            Moorings   $((td - tc)) over $N actions, status alone $status," \
		"$scans scans $scansum, per action $TR_per"
}

# lat prints one latency field of an app over every round, one per line.
lat() {
	r=1
	while [ "$r" -le "$ROUNDS" ]; do
		eval "echo \$${1}_${2}_$r"
		r=$((r + 1))
	done
}

fails=0
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
	latency Moorings "moorings://action?name=left-half" "moorings://action?name=right-half" "$round"
	pause Pause
	paused=1
	sleep 1
	run Rectangle "rectangle://execute-action?name=left-half" "rectangle://execute-action?name=right-half" "$round"
	latency Rectangle "rectangle://execute-action?name=left-half" "rectangle://execute-action?name=right-half" "$round"
	run Loop "loop://direction/leftHalf" "loop://direction/rightHalf" "$round"
	latency Loop "loop://direction/leftHalf" "loop://direction/rightHalf" "$round"
	pause Resume
	paused=0
	round=$((round + 1))
done
tripsphase
osascript -e "tell application id \"$probe\" to quit" >/dev/null
repid

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
# sort -n reads a missed percentile as zero, so a miss can only lower a median: a rival's bound
# gets tighter, and a Moorings miss fails on its count.
l95_m=$(median $(lat L95 Moorings))
l95_r=$(median $(lat L95 Rectangle))
l50_m=$(median $(lat L50 Moorings))
l50_r=$(median $(lat L50 Rectangle))
l50_l=$(median $(lat L50 Loop))
lbad_m=$(echo $(lat LM Moorings) $(lat LW Moorings) | awk '{ s = 0; for (i = 1; i <= NF; i++) s += $i; print s }')

echo
echo "active           per action over $ROUNDS rounds: Moorings ${all_m}s, Rectangle ${all_r}s, Loop ${all_l}s"
echo "$act_m $act_r|$all_m|$all_r" | awk -F'|' '{
	split($1, med, " ")
	n = split($2, m, " ")
	split($3, r, " ")
	rounds = ""
	for (i = 1; i <= n; i++) rounds = rounds sprintf(" %.2f", m[i] / r[i])
	printf "active ratio Moorings/Rectangle: %.2f (rounds%s)\n", med[1] / med[2], rounds
}'
echo "paused           Moorings   median cpu per foreign move: Rectangle phases $pau_m s, Loop phases $pau_l s"
echo "latency          median over $ROUNDS rounds in ms: Moorings p50 $l50_m p95 $l95_m, Rectangle p50 $l50_r p95 $l95_r, Loop p50 $l50_l p95 $(median $(lat L95 Loop))"
echo
echo "verdict"
ok=$(echo "$mem_m $mem_r $mem_l" | awk '{ print ($1 <= 1.5 * $2 && $1 <= $3) ? 1 : 0 }')
check Memory "$ok" "measured ${mem_m}MB, bound min(1.5 x Rectangle ${mem_r}MB, Loop ${mem_l}MB)"
ok=$(echo "$D_idle_Moorings $passes" | awk '{ print ($1 <= 0.03 && $2 == 0) ? 1 : 0 }')
check Idle "$ok" "measured ${D_idle_Moorings} s and $passes pass lines, bound 0.03 s and 0 pass lines"
ok=$(echo "$act_m $act_r $act_l $BOUND" | awk '{ print ($1 <= $4 * $2 && $1 <= $3) ? 1 : 0 }')
check Active "$ok" "median ${act_m} s per action, ratio $(echo "$act_m $act_r" | awk '{ printf "%.2f", $1 / $2 }'), bound min(${BOUND} x Rectangle ${act_r}, Loop ${act_l})"
ok=$(echo "$pau_m" | awk '{ print ($1 <= 0.001) ? 1 : 0 }')
check Paused "$ok" "measured ${pau_m} s per foreign move, bound 0.001 s"
# numeric is 1 when every argument is a plain decimal number, so a missed percentile fails a check.
numeric() { printf '%s\n' "$@" | awk '!/^[0-9]+(\.[0-9]+)?$/ { bad = 1 } END { print bad ? 0 : 1 }'; }
ok=0
if [ "$(numeric "$l95_m" "$l95_r" "$l50_l")" = 1 ] && [ "$lbad_m" = 0 ]; then
	ok=$(echo "$l95_m $l95_r $l50_l" | awk '{ print ($1 <= $2 && $1 <= $3) ? 1 : 0 }')
fi
check Latency "$ok" "Moorings p95 ${l95_m} ms with $lbad_m missed or wrong, bound min(Rectangle p95 ${l95_r}, Loop p50 ${l50_l}) ms and 0"
ok=0
if [ "$(numeric "$l50_m" "$l50_r" "$l50_l")" = 1 ]; then
	ok=$(echo "$l50_m $l50_r $l50_l" | awk '{ print ($1 <= $2 && $1 <= $3) ? 1 : 0 }')
fi
check Lat50 "$ok" "Moorings p50 ${l50_m} ms, bound min(Rectangle p50 ${l50_r}, Loop p50 ${l50_l}) ms"
ok=$(echo "$TR_per $TRIPS_BOUND" | awk '{ print ($1 <= $2) ? 1 : 0 }')
check Trips "$ok" "per action $TR_per, bound $TRIPS_BOUND"

[ "$fails" -eq 0 ] || exit 1
exit 0
