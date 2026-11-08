# Shared helpers for bench.sh and use.sh, sourced by both. It defines functions only.

# pid prints the first pid of the named app's binary under /Applications.
pid() { pgrep -f "/Applications/$1.app/Contents/MacOS/$1" | head -1; }

# probebin runs the probe binary make probe built, with its arguments.
probebin() { "$(dirname "$0")/../.build/MooringsProbe.app/Contents/MacOS/MooringsProbe" "$@"; }

# cpu prints the cumulative CPU seconds of a pid, to the microsecond, as the probe reads them.
cpu() { probebin --cpu "$1"; }

# spent prints the CPU seconds pid $1 used since the reading $2. A process gone since then, or a
# reading that failed, prints 0.0000: medians sort it low, so a crashed rival can only tighten its
# own bound.
spent() {
	if [ -n "$2" ] && now=$(cpu "$1"); then
		echo "$now $2" | awk '{ printf "%.4f", $1 - $2 }'
	else
		printf '0.0000'
	fi
}

# repid refreshes the recorded P_<app> of each app in $apps before a phase. A rival that crashed is
# measured under its new pid, opened again if nothing brought it back. Moorings under another pid or
# none ends the run with 2, since every figure must describe one process.
repid() {
	for a in $apps; do
		eval "old=\$P_$a"
		new=$(pid "$a")
		if [ "$a" = Moorings ]; then
			if [ "$new" != "$old" ]; then
				echo "$(basename "$0"): Moorings pid $old is gone, the app has pid '$new' now" >&2
				exit 2
			fi
			continue
		fi
		if [ -z "$new" ]; then
			open -g "/Applications/$a.app"
			sleep 3
			new=$(pid "$a")
		fi
		if [ -z "$new" ]; then
			echo "$(basename "$0"): $a pid $old is gone and it did not open again" >&2
			exit 2
		fi
		if [ "$new" != "$old" ]; then
			echo "$a restarted: pid $old is now $new"
			eval "P_$a=\$new"
		fi
	done
}

# median prints the middle of its numeric arguments, the lower middle for an even count.
median() { printf '%s\n' "$@" | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'; }

# trips prints the Moorings round trip count from a fresh status line. The caller sets subsystem.
# shellcheck disable=SC2154
trips() {
	open -g moorings://status
	sleep 1.5
	/usr/bin/log show --last 5s --predicate "subsystem == \"$subsystem\"" 2>/dev/null |
		grep -o 'trips=[0-9]*' | tail -1 | cut -d= -f2
}
