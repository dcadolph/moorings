#!/bin/sh
# Print the const values files the release build wrote for one module, for the Shortcuts metadata.
#
# Usage: intents_consts.sh <bin path> <arch> <module> <sources> [-- <rebuild command>]
#
# <bin path> is what `swift build -c release --show-bin-path` prints, and <sources> is the folder that
# holds the module's Swift sources. The files are read only from the layout that bin path belongs to,
# so files an earlier toolchain left in another layout are never used. A bin path ending in
# Products/Release keeps them under the sibling Intermediates.noindex, in the module's target folder
# for <arch>. Any other bin path keeps them in <bin path>/<module>.build.
#
# A file that is not newer than the newest source is stale. The build skips a source whose time moved
# while its content did not, so a branch switch and back leaves good files that read as stale, and it
# writes a missing file again without compiling. With a rebuild command, the script deletes the stale
# files, runs the command with its output on stderr, and reads again. A file still stale, or no file
# at all, fails the run.
set -u

usage="usage: intents_consts.sh <bin path> <arch> <module> <sources> [-- <rebuild command>]"
if [ $# -lt 4 ] || { [ $# -gt 4 ] && { [ "$5" != "--" ] || [ $# -eq 5 ]; }; }; then
	echo "$usage" >&2
	exit 2
fi
bin=$1
arch=$2
module=$3
sources=$4
shift 4
[ $# -gt 0 ] && shift

case $bin in
*/Products/Release) build=$(dirname "$(dirname "$(dirname "$bin")")") ;;
*) build=$(dirname "$(dirname "$bin")") ;;
esac

# consts lists the module's const values files in the layout of the bin path, narrowed by the find
# terms given as arguments.
consts() {
	case $bin in
	*/Products/Release)
		find "$(dirname "$(dirname "$bin")")/Intermediates.noindex" -name '*.swiftconstvalues' \
			\( -path "*/Release/$module.build/Objects-normal/$arch/*" \
			-o -path "*/Release/$module-p.build/Objects-normal/$arch/*" \) "$@" 2>/dev/null
		;;
	*)
		find "$bin/$module.build" -name '*.swiftconstvalues' "$@" 2>/dev/null
		;;
	esac | sort
}

# none fails the run when the layout holds no const values for the module, naming every const values
# file under the build folder so a layout change shows in the log.
none() {
	echo "intents_consts: no const values for $module ($arch) in the layout of $bin" >&2
	echo "intents_consts: const values under $build:" >&2
	find "$build" -name '*.swiftconstvalues' >&2
	exit 1
}

found=$(consts)
[ -n "$found" ] || none

newest=$(find "$sources" -name '*.swift' -exec stat -f '%m %N' {} + 2>/dev/null |
	sort -n | tail -1 | cut -d' ' -f2-)
if [ -z "$newest" ]; then
	echo "intents_consts: no Swift sources under $sources" >&2
	exit 1
fi

stale=$(consts ! -newer "$newest")
if [ -n "$stale" ] && [ $# -gt 0 ]; then
	echo "intents_consts: const values not newer than $newest, building them again:" >&2
	echo "$stale" >&2
	echo "$stale" | while IFS= read -r file; do rm -f "$file"; done
	if ! "$@" >&2; then
		echo "intents_consts: rebuild failed: $*" >&2
		exit 1
	fi
	found=$(consts)
	[ -n "$found" ] || none
	stale=$(consts ! -newer "$newest")
fi
if [ -n "$stale" ]; then
	echo "intents_consts: stale const values, not newer than $newest:" >&2
	echo "$stale" >&2
	exit 1
fi

echo "$found"
