#!/bin/sh
# Measure Moorings, Rectangle and Loop over a scripted desk like a working day and fail unless
# Moorings uses no more CPU than Loop and no more than the baseline.
#
# Usage: use.sh
#
# Release run: ROUNDS=3 make use
#
# Environment:
#   WALK    Seconds of each walk (default 120).
#   DRAGS   Seconds of each round's drag part, 0 to skip it (default 60).
#   ROUNDS  Walks, one after another (default 3).
#
# Each round the running probe walks for WALK seconds: every 2 s it switches to TextEdit and back,
# every 5 s it moves its window 300 points and back in 20 steps of 20 ms each way, every 7 s it
# widens it by 100 points and back the same way, and every 11 s it opens a second window for 1 s.
# It posts no input events. All three apps run and none is paused, since the walk is the desk and
# not an action aimed at one app. CPU is each app's user plus system time delta over the walk, read
# in microseconds with proc_pid_rusage. Trips is the Moorings Accessibility round trip count over
# the round from its status line, which includes the one scan the second status read makes.
#
# After each walk a drag part, measured apart, posts real mouse events for DRAGS seconds: every 3 s
# a title bar drag of a probe window 300 points out and back, and 1.5 s later a text selection drag
# inside it. It needs the probe trusted for Accessibility, which a Developer ID signature keeps
# across rebuilds (SIGN_ID for make probe), and the desk left alone while it runs. An untrusted
# probe skips the part and says so. Its numbers are printed for information.
#
#   Use  Moorings median CPU over the rounds at most Loop's median and at most BASELINE. Rectangle
#        observes no windows between shortcuts and is printed for information.
#
# Needs Moorings, Rectangle and Loop running from /Applications, Accessibility trusted for Moorings,
# and the probe registered by make probe. Opens a scratch document in TextEdit, closes it at the end
# and quits TextEdit only if it was not running before. Exits 2 when something is missing, 1 on a
# FAIL, 0 on a PASS.
set -u

# BASELINE is the first measured Moorings median in seconds, set from a passing run. It only ever
# goes down. Empty until then, which leaves Loop as the only bound.
BASELINE=""

WALK=${WALK:-120}
DRAGS=${DRAGS:-60}
ROUNDS=${ROUNDS:-3}
apps="Moorings Rectangle Loop"
subsystem="com.dcadolph.moorings"
probe="com.dcadolph.moorings.probe"
textedit="com.apple.TextEdit"
tmp=$(mktemp -d)
started_textedit=0

. "$(dirname "$0")/measure.sh"

# trips prints the Moorings round trip count from a fresh status line.
trips() {
	open -g moorings://status
	sleep 1
	/usr/bin/log show --last 5s --predicate "subsystem == \"$subsystem\"" 2>/dev/null |
		grep -o 'trips=[0-9]*' | tail -1 | cut -d= -f2
}

# cleanup closes the scratch document, quits TextEdit if this run started it, quits the probe and
# removes scratch files.
cleanup() {
	osascript -e "tell application id \"$textedit\" to close (every document whose path is \"$tmp/desk.txt\") saving no" \
		>/dev/null 2>&1
	if [ "$started_textedit" = 1 ]; then
		osascript -e "tell application id \"$textedit\" to quit saving no" >/dev/null 2>&1
	fi
	osascript -e "tell application id \"$probe\" to quit" >/dev/null 2>&1
	rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

missing=""
for a in $apps; do
	p=$(pid "$a")
	[ -n "$p" ] || missing="$missing $a"
	eval "P_$a=\$p"
done
if [ -n "$missing" ]; then
	echo "use: no running process for:$missing" >&2
	exit 2
fi
if [ ! -d "$(dirname "$0")/../.build/MooringsProbe.app" ]; then
	echo "use: no probe, run make probe in mac/" >&2
	exit 2
fi
open -g moorings://status
sleep 2
if ! /usr/bin/log show --last 10s --predicate "subsystem == \"$subsystem\"" 2>/dev/null |
	grep -q 'trusted=true'; then
	echo "use: Moorings does not report trusted=true, Accessibility is not granted" >&2
	exit 2
fi

pgrep -xq TextEdit || started_textedit=1
echo "a scratch document for the use measure" >"$tmp/desk.txt"
open -b "$textedit" "$tmp/desk.txt"
osascript -e "tell application id \"$probe\" to quit" >/dev/null 2>&1
sleep 1
open -b "$probe"
# Wait out the 30 s in which Moorings reads every app for a launched app's first window.
sleep 35

# drag_round runs the drag part of round $1 and prints its line, or turns the part off for the rest
# of the run when the probe is not trusted.
drag_round() {
	d0=$(trips)
	for a in $apps; do
		eval "D0_$a=\$(cpu \$P_$a)"
	done
	if ! dline=$(probebin --drags "$DRAGS"); then
		echo "use: the probe sent no drags line" >&2
		exit 2
	fi
	case $dline in
	"drags "*) ;;
	"error not trusted"*)
		echo "drags skipped: the probe is not trusted for Accessibility"
		DRAGS=0
		return
		;;
	*)
		echo "use: the probe refused the drags: $dline" >&2
		exit 2
		;;
	esac
	for a in $apps; do
		eval "base=\$D0_$a p=\$P_$a"
		d=$(echo "$(cpu "$p") $base" | awk '{ printf "%.4f", $1 - $2 }')
		eval "G_${a}_$1=$d"
	done
	d1=$(trips)
	dtr=unread
	if [ -n "$d0" ] && [ -n "$d1" ]; then
		dtr=$((d1 - d0))
	fi
	eval "echo \"drags round $1: Moorings \$G_Moorings_$1 s, Rectangle \$G_Rectangle_$1 s, Loop \$G_Loop_$1 s, Moorings trips $dtr, $dline\""
	dragged=$1
}

dragged=0
round=1
while [ "$round" -le "$ROUNDS" ]; do
	t0=$(trips)
	for a in $apps; do
		eval "C0_$a=\$(cpu \$P_$a)"
	done
	if ! line=$(probebin --walk "$WALK" "$textedit"); then
		echo "use: the probe sent no walk line" >&2
		exit 2
	fi
	case $line in
	"walk "*) ;;
	*)
		echo "use: the probe refused the walk: $line" >&2
		exit 2
		;;
	esac
	for a in $apps; do
		eval "base=\$C0_$a p=\$P_$a"
		d=$(echo "$(cpu "$p") $base" | awk '{ printf "%.4f", $1 - $2 }')
		eval "U_${a}_$round=$d"
	done
	t1=$(trips)
	tr=unread
	if [ -n "$t0" ] && [ -n "$t1" ]; then
		tr=$((t1 - t0))
	fi
	eval "echo \"use round $round: Moorings \$U_Moorings_$round s, Rectangle \$U_Rectangle_$round s, Loop \$U_Loop_$round s, Moorings trips $tr, $line\""
	if [ "$DRAGS" -gt 0 ]; then
		drag_round "$round"
	fi
	round=$((round + 1))
done

# rounds prints one app's use CPU over every round, one per line, or with a second argument G its
# drag part CPU over the rounds that ran one.
rounds() {
	r=1
	n=$ROUNDS
	[ "${2:-U}" = G ] && n=$dragged
	while [ "$r" -le "$n" ]; do
		eval "echo \$${2:-U}_${1}_$r"
		r=$((r + 1))
	done
}

use_m=$(median $(rounds Moorings))
use_r=$(median $(rounds Rectangle))
use_l=$(median $(rounds Loop))
spread=$(rounds Moorings | sort -n | awk -v m="$use_m" 'NR == 1 { lo = $1 } { hi = $1 } END { printf "%.0f", m > 0 ? (hi - lo) * 100 / m : 0 }')
echo
echo "use              median over $ROUNDS rounds of ${WALK} s: Moorings $use_m s (spread ${spread} pct of median), Rectangle $use_r s, Loop $use_l s"
if [ "$dragged" -gt 0 ]; then
	echo "drags            median over $dragged rounds of ${DRAGS} s: Moorings $(median $(rounds Moorings G)) s, Rectangle $(median $(rounds Rectangle G)) s, Loop $(median $(rounds Loop G)) s, for information"
fi
echo
echo "verdict"
bound="Loop ${use_l} s, no baseline set yet"
ok=$(echo "$use_m $use_l" | awk '{ print ($1 <= $2) ? 1 : 0 }')
if [ -n "$BASELINE" ]; then
	bound="min(Loop ${use_l} s, baseline ${BASELINE} s)"
	ok=$(echo "$use_m $use_l $BASELINE" | awk '{ print ($1 <= $2 && $1 <= $3) ? 1 : 0 }')
fi
if [ "$ok" = 1 ]; then
	printf "%-8s PASS  %s\n" Use "measured ${use_m} s, bound $bound"
	exit 0
fi
printf "%-8s FAIL  %s\n" Use "measured ${use_m} s, bound $bound"
exit 1
