#!/bin/sh
# Sample one process's CPU percent and energy impact over a fixed window.
#
# Usage: energy.sh [-m minutes] [-i seconds] [-c] [-u left-url,right-url] [-p] app-name
#
#   -m  Minutes to sample (default 10).
#   -i  Seconds between samples (default 5).
#   -c  Churn: the app itself moves TextEdit between halves every 2 seconds.
#   -u  Churn links for an app with no built-in route (Moorings, Rectangle and Loop have one).
#   -p  Also sample with powermetrics (needs sudo).
#
# Prints the raw samples to stderr and one summary line to stdout:
#   app=<name> mode=<idle|churn> samples=<n> cpu_mean=<pct> energy_mean=<impact>
set -eu

minutes=10
interval=5
churn=0
urls=""
pm=0

usage() {
	sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

if [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi
while getopts "m:i:cu:ph" opt; do
	case "$opt" in
	m) minutes=$OPTARG ;;
	i) interval=$OPTARG ;;
	c) churn=1 ;;
	u) urls=$OPTARG ;;
	p) pm=1 ;;
	h) usage; exit 0 ;;
	*) usage >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
if [ $# -ne 1 ]; then
	usage >&2
	exit 2
fi
app=$1

pid=$(pgrep -x "$app" | head -1 || true)
if [ -z "$pid" ]; then
	echo "energy: $app is not running" >&2
	exit 1
fi

samples=$((minutes * 60 / interval))
mode=idle
mover=""
pmpid=""
pmout=""

cleanup() {
	[ -n "$mover" ] && kill "$mover" 2>/dev/null || true
	[ -n "$pmpid" ] && sudo kill "$pmpid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if [ "$churn" -eq 1 ]; then
	mode=churn
	# Churn goes through the measured app's own links, sent to the running copy by path so a
	# second copy elsewhere on disk never launches. Moving a window from outside the app would
	# measure nothing the app does.
	bundle=$(ps -o comm= -p "$pid" | sed 's|/Contents/MacOS/.*||')
	if [ -z "$urls" ]; then
		case "$app" in
		Moorings) urls="moorings://action?name=left-half,moorings://action?name=right-half" ;;
		Rectangle) urls="rectangle://execute-action?name=left-half,rectangle://execute-action?name=right-half" ;;
		Loop) urls="loop://direction/left,loop://direction/right" ;;
		*)
			echo "energy: no churn links for $app, pass -u left-url,right-url" >&2
			exit 2
			;;
		esac
	fi
	left=${urls%%,*}
	right=${urls#*,}
	open -a TextEdit
	sleep 2
	osascript -e 'tell application "TextEdit" to if (count of documents) is 0 then make new document'
	(
		url=$left
		while :; do
			open -g -a "$bundle" "$url" >/dev/null 2>&1 || true
			if [ "$url" = "$left" ]; then url=$right; else url=$left; fi
			sleep 2
		done
	) &
	mover=$!
fi

if [ "$pm" -eq 1 ]; then
	pmout=$(mktemp)
	sudo powermetrics --samplers tasks --show-process-energy -i $((interval * 1000)) -n "$samples" >"$pmout" 2>/dev/null &
	pmpid=$!
fi

# The first top sample has no prior interval to measure against, so take one extra and drop it.
top -l $((samples + 1)) -s "$interval" -pid "$pid" -stats pid,cpu,power |
	awk -v pid="$pid" -v app="$app" -v mode="$mode" '
		$1 == pid { n++; if (n == 1) next; print "sample", n - 1, "cpu", $2, "energy", $3 > "/dev/stderr"; c += $2; e += $3; k++ }
		END { if (k == 0) exit 1; printf "app=%s mode=%s samples=%d cpu_mean=%.2f energy_mean=%.2f\n", app, mode, k, c / k, e / k }'

if [ -n "$pmpid" ]; then
	wait "$pmpid" 2>/dev/null || true
	pmpid=""
	awk -v app="$app" '$1 == app { c += $3; e += $(NF); k++ }
		END { if (k) printf "powermetrics app=%s samples=%d cpu_ms_per_s_mean=%.2f energy_impact_mean=%.2f\n", app, k, c / k, e / k }' "$pmout"
	rm -f "$pmout"
fi
