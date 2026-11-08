#!/bin/sh
# Measure Moorings, Rectangle and Loop over a scripted desk like a working day and fail unless
# Moorings stays at or under its CPU baseline and, while paused, its round trip bound.
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
#   Use     Moorings median CPU over the rounds at most BASELINE. Rectangle and Loop are printed for
#           information: Moorings handles every window event to hold the layout, which they do not.
#   Paused  One more walk with Moorings paused, at most PAUSED_TRIPS round trips net of one status
#           request, measured by two status reads in a row while paused.
#
# Needs Moorings, Rectangle and Loop running from /Applications, Accessibility trusted for Moorings,
# and the probe registered by make probe. Opens a scratch document in TextEdit, closes it at the end
# and quits TextEdit only if it was not running before. Moorings is resumed again on exit. Exits 2
# when something is missing, 1 on a FAIL, 0 on a PASS.
set -u

# BASELINE is the Moorings bound in seconds, the highest round of the 11-04 run on v1.18.1 rounded up
# to 0.01 s. It only ever goes down.
BASELINE=1.28
# PAUSED_TRIPS is the paused walk's bound for a 120 s walk, that run's 620 plus the rounds' spread of
# 10. It only ever goes down.
PAUSED_TRIPS=630

WALK=${WALK:-120}
DRAGS=${DRAGS:-60}
ROUNDS=${ROUNDS:-3}
USE_BOUND=${MOORINGS_USE_BASELINE:-$BASELINE}
PAUSED_BOUND=${MOORINGS_PAUSED_TRIPS_BOUND:-$PAUSED_TRIPS}
apps="Moorings Rectangle Loop"
subsystem="com.dcadolph.moorings"
probe="com.dcadolph.moorings.probe"
textedit="com.apple.TextEdit"
tmp=$(mktemp -d)
started_textedit=0
paused=0
fails=0

. "$(dirname "$0")/measure.sh"

# cleanup resumes Moorings if it is paused, closes the scratch document, quits TextEdit if this run
# started it, quits the probe and removes scratch files.
cleanup() {
	if [ "$paused" = 1 ]; then
		paused=0
		pause Resume
	fi
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
	repid
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
		d=$(spent "$p" "$base")
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
	repid
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
		d=$(spent "$p" "$base")
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

# The paused walk reads the status cost while paused, since a paused status request reads less.
pause Pause
paused=1
sleep 1
pa=$(trips)
pb=$(trips)
repid
p0=$(trips)
if ! pline=$(probebin --walk "$WALK" "$textedit"); then
	echo "use: the probe sent no paused walk line" >&2
	exit 2
fi
p1=$(trips)
pause Resume
paused=0
if [ -z "$pa" ] || [ -z "$pb" ] || [ -z "$p0" ] || [ -z "$p1" ]; then
	echo "use: Moorings sent no trips= status line in the paused walk" >&2
	exit 2
fi
pstatus=$((pb - pa))
pnet=$((p1 - p0 - pstatus))
echo "paused walk: Moorings trips $((p1 - p0)), status alone $pstatus, net $pnet, $pline"
repid

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
spread=$(rounds Moorings | sort -n | awk -v m="$use_m" 'NR == 1 { lo = $1 } { hi = $1 } END { printf "%.0f", (m > 0 ? (hi - lo) * 100 / m : 0) }')
echo
echo "use              median over $ROUNDS rounds of ${WALK} s: Moorings $use_m s (spread ${spread} pct of median), Rectangle $use_r s, Loop $use_l s"
if [ "$dragged" -gt 0 ]; then
	echo "drags            median over $dragged rounds of ${DRAGS} s: Moorings $(median $(rounds Moorings G)) s, Rectangle $(median $(rounds Rectangle G)) s, Loop $(median $(rounds Loop G)) s, for information"
fi
echo
echo "verdict"
ok=$(echo "$use_m $USE_BOUND" | awk '{ print ($1 <= $2) ? 1 : 0 }')
check Use "$ok" "measured ${use_m} s, bound baseline ${USE_BOUND} s, Rectangle ${use_r} s and Loop ${use_l} s for information"
ok=$(echo "$pnet $PAUSED_BOUND" | awk '{ print ($1 <= $2) ? 1 : 0 }')
check Paused "$ok" "measured $pnet net round trips, bound $PAUSED_BOUND"

[ "$fails" -eq 0 ] || exit 1
exit 0
