#!/bin/sh
# Print the const values files the release build wrote for one module, for the Shortcuts metadata.
#
# Usage: intents_consts.sh <bin path> <arch> <module> <sources>
#
# <bin path> is what `swift build -c release --show-bin-path` prints, and <sources> is the folder that
# holds the module's Swift sources. The files are read only from the layout that bin path belongs to,
# so files an earlier toolchain left in another layout are never used. A bin path ending in
# Products/Release keeps them under the sibling Intermediates.noindex, in the module's target folder
# for <arch>. Any other bin path keeps them in <bin path>/<module>.build.
#
# A release build compiles the module in one job, so every file it wrote is newer than every source.
# A file that is not newer than the newest source is stale and fails the run, and so does finding no
# file at all.
set -u

if [ $# -ne 4 ]; then
	echo "usage: intents_consts.sh <bin path> <arch> <module> <sources>" >&2
	exit 2
fi
bin=$1
arch=$2
module=$3
sources=$4

case $bin in
*/Products/Release) build=$(dirname "$(dirname "$(dirname "$bin")")") ;;
*) build=$(dirname "$(dirname "$bin")") ;;
esac

# consts lists the module's const values files in the layout of the bin path, narrowed by the find
# terms in $@.
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

found=$(consts)
if [ -z "$found" ]; then
	echo "intents_consts: no const values for $module ($arch) in the layout of $bin" >&2
	echo "intents_consts: const values under $build:" >&2
	find "$build" -name '*.swiftconstvalues' >&2
	exit 1
fi

newest=$(find "$sources" -name '*.swift' -exec stat -f '%m %N' {} + 2>/dev/null |
	sort -n | tail -1 | cut -d' ' -f2-)
if [ -z "$newest" ]; then
	echo "intents_consts: no Swift sources under $sources" >&2
	exit 1
fi

stale=$(consts ! -newer "$newest")
if [ -n "$stale" ]; then
	echo "intents_consts: stale const values, not newer than $newest:" >&2
	echo "$stale" >&2
	exit 1
fi

echo "$found"
