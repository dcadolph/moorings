# Makefile gates the core package on line coverage: each target must stay at or above its floor.
# A floor is the first measured line coverage rounded down to 5. Later units raise it, never lower it.

SHELL := /bin/bash

# CORE_FLOOR is the floor for MooringsCore, measured 97.85 percent on 10-28.
CORE_FLOOR ?= 95
# ENGINE_FLOOR is the floor for MooringsEngine, measured 87.79 percent on 10-28.
ENGINE_FLOOR ?= 85

.PHONY: coverage

# coverage runs the tests with coverage on, prints the per-file table, and fails below a floor.
coverage:
	swift test --enable-code-coverage -Xswiftc -warnings-as-errors
	@bin="$$(swift build --show-bin-path)"; \
	tests="$$bin/MooringsCorePackageTests.xctest/Contents/MacOS/MooringsCorePackageTests"; \
	profile="$$bin/codecov/default.profdata"; \
	for f in "$$tests" "$$profile"; do \
		test -f "$$f" || { echo "coverage: missing $$f" >&2; exit 1; }; \
	done; \
	xcrun llvm-cov report "$$tests" -instr-profile="$$profile" Sources/MooringsCore Sources/MooringsEngine; \
	fail=0; \
	for pair in MooringsCore:$(CORE_FLOOR) MooringsEngine:$(ENGINE_FLOOR); do \
		target="$${pair%%:*}"; floor="$${pair##*:}"; \
		lines="$$(xcrun llvm-cov report "$$tests" -instr-profile="$$profile" "Sources/$$target" \
			| awk '$$1 == "TOTAL" { sub("%", "", $$10); print $$10 }')"; \
		echo "coverage: $$target lines $$lines percent, floor $$floor"; \
		awk -v l="$$lines" -v f="$$floor" 'BEGIN { exit !(l != "" && l + 0 >= f) }' || fail=1; \
	done; \
	exit $$fail
