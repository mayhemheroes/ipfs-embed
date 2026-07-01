#!/usr/bin/env bash
#
# mayhem/test.sh — RUN the pre-built behavioral-oracle test suite (mayhem/oracle),
# known-answer tests over the exact ipfs_embed::Block::decode path the decode-block
# fuzzer drives. build.sh compiled it to /mayhem/oracle-tests/decode_kat.
# Asserts DECODED VALUES (not just exit 0) so neutering the decoder fails the oracle.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN=/mayhem/oracle-tests/decode_kat
[ -x "$BIN" ] || { echo "ERROR: oracle test binary $BIN missing — build.sh bug" >&2; emit_ctrf "cargo-test" 0 1 0; exit 1; }

# libtest prints a final line: "test result: ok. N passed; M failed; K ignored; ..."
out="$("$BIN" --test-threads=1 2>&1)"
echo "$out"
line="$(printf '%s\n' "$out" | grep -E '^test result:' | tail -1)"
passed=$(printf '%s\n' "$line" | grep -oE '[0-9]+ passed'  | grep -oE '[0-9]+' || echo 0)
failed=$(printf '%s\n' "$line" | grep -oE '[0-9]+ failed'  | grep -oE '[0-9]+' || echo 0)
skipped=$(printf '%s\n' "$line" | grep -oE '[0-9]+ ignored' | grep -oE '[0-9]+' || echo 0)
: "${passed:=0}"; : "${failed:=0}"; : "${skipped:=0}"

# No result line at all means the binary didn't run its tests -> a failure, not a pass.
if [ -z "$line" ]; then
  echo "ERROR: no libtest result line — treating as failure" >&2
  emit_ctrf "cargo-test" 0 1 0
  exit 1
fi

emit_ctrf "cargo-test" "$passed" "$failed" "$skipped"
