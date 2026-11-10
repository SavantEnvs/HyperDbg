#!/usr/bin/env bash
#
# mayhem/build.sh — build the script-engine fuzz harness (sanitized) and the functional-test probe
# (normal flags). Runs in the commit image as `mayhem` in /mayhem, offline and re-runnable: the
# script engine is plain C with no third-party dependencies, so there is nothing to fetch.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"

cd "$SRC"
SE=hyperdbg/script-engine
OUT=mayhem/build
FUZZ_OBJ=$OUT/fuzz-obj
TEST_OBJ=$OUT/test-obj
rm -rf "$OUT"
mkdir -p "$FUZZ_OBJ" "$TEST_OBJ"

# The user-mode script engine, as hyperdbg/script-engine/CMakeLists.txt builds it on Linux
# (symbol-parser and the Win32 include resolver are replaced by the Linux stubs).
SOURCES="
$SE/code/common.c
$SE/code/globals.c
$SE/code/hardware.c
$SE/code/parse-table.c
$SE/code/scanner.c
$SE/code/script-engine.c
$SE/code/script_include-linux.c
$SE/code/symbol-stub-linux.c
$SE/code/type.c
hyperdbg/include/platform/user/code/platform-lib-calls.c
"
INCLUDES="-I$SE/header -Ihyperdbg/include -I$SE -Ihyperdbg/script-eval"
# C23 so the SDK headers' bare static_assert compiles.
COMMON="-std=gnu2x -DHYPERDBG_SCRIPT_ENGINE $INCLUDES -w"

compile() { # <objdir> <flags...> -- <sources...>
  local dir="$1"; shift
  local flags=() ; while [ "$1" != "--" ]; do flags+=("$1"); shift; done; shift
  printf '%s\n' "$@" | xargs -P "$MAYHEM_JOBS" -I{} sh -c \
    '"$0" "$@" -c "{}" -o "'"$dir"'/$(basename "{}").o"' "$CC" "${flags[@]}"
}

# 1) Sanitized + SanCov-instrumented engine for the fuzzer (DWARF <= 3).
# shellcheck disable=SC2086
compile "$FUZZ_OBJ" $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1 $COMMON -- $SOURCES

# 2) Harness, once with libFuzzer and once with the run-once driver; LSan is turned off at link time.
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$OUT/lsan_off.o"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS -O1 $COMMON -c mayhem/fuzz_script_parse/harness.c -o "$OUT/harness.o"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/standalone_main.o"
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OUT/harness.o" "$FUZZ_OBJ"/*.o "$OUT/lsan_off.o" -lm -o "$OUT/fuzz_script_parse"
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OUT/standalone_main.o" "$OUT/harness.o" "$FUZZ_OBJ"/*.o "$OUT/lsan_off.o" -lm -o "$OUT/fuzz_script_parse-standalone"

# 3) Functional-test probe with the project's normal flags (no sanitizer, no -gdwarf-3).
# shellcheck disable=SC2086
compile "$TEST_OBJ" -O1 $COVERAGE_FLAGS $COMMON -- $SOURCES
# shellcheck disable=SC2086
$CC -O1 $COVERAGE_FLAGS $COMMON -c mayhem/selftest.c -o "$OUT/selftest.o"
# shellcheck disable=SC2086
$CC $COVERAGE_FLAGS "$OUT/selftest.o" "$TEST_OBJ"/*.o -lm -o "$OUT/script_selftest"

ls -l "$OUT/fuzz_script_parse" "$OUT/fuzz_script_parse-standalone" "$OUT/script_selftest"
