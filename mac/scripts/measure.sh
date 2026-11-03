# Shared helpers for bench.sh and use.sh, sourced by both. It defines functions only.

# pid prints the first pid of the named app's binary under /Applications.
pid() { pgrep -f "/Applications/$1.app/Contents/MacOS/$1" | head -1; }

# probebin runs the probe binary make probe built, with its arguments.
probebin() { "$(dirname "$0")/../.build/MooringsProbe.app/Contents/MacOS/MooringsProbe" "$@"; }

# cpu prints the cumulative CPU seconds of a pid, to the microsecond, as the probe reads them.
cpu() { probebin --cpu "$1"; }

# median prints the middle of its numeric arguments, the lower middle for an even count.
median() { printf '%s\n' "$@" | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'; }
