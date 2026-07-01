#!/usr/bin/env bash
#
# mayhem/build.sh — build this repo's cargo-fuzz target(s) as sanitized libFuzzer
# binaries (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS). EDIT per repo.
#
# Runs inside the commit image (RUST mayhem/Dockerfile) as `mayhem` in /mayhem.
# The Rust toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo
# (pinned by the Dockerfile ENV — absolute, $HOME-independent).
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
#   - This FIRST build (in CI, online) populates the cargo registry under $CARGO_HOME.
#   - The PATCH re-run resolves crates from that cache. The rlenv runtime exports
#     CARGO_NET_OFFLINE=true for the re-run so cargo won't try to refresh the
#     crates.io index over the (absent) network — so do NOT hard-code `--offline`
#     here (it would break this first, online build).
#   - For a FULLY self-contained image (no runtime flag needed) instead vendor:
#       cargo vendor --versioned-dirs vendor   # commit vendor/ + a .cargo/config.toml
#     with [source.crates-io] replace-with = "vendored-sources".
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# Sanitizer selection. The base image exports $SANITIZER_FLAGS as *clang* flags
# (-fsanitize=...) which rustc rejects — so we DON'T thread that string into RUSTFLAGS
# (SKILL: "ASan via RUSTFLAGS, not $SANITIZER_FLAGS"). We only READ $SANITIZER_FLAGS to
# honor the off-switch: `--build-arg SANITIZER_FLAGS=` (empty) => build WITHOUT the
# rustc sanitizer (natural-crash / anti-reward-hack sabotage build). Non-empty => ASan
# (the OSS-Fuzz Rust path; UBSan is not a rustc sanitizer, so ASan is the halting one).
if [ -n "${SANITIZER_FLAGS:-}" ]; then
  RUST_SANITIZER="-Zsanitizer=address"
else
  RUST_SANITIZER=""
fi

# Debug-info contract (SPEC §6.2 item 10): Mayhem triage needs DWARF < 4. rustc defaults
# to DWARF 5, so force DWARF 3. $RUST_DEBUG_FLAGS is the threaded, overridable knob;
# -gdwarf-3 keeps any C/C++ build scripts (prost/ring) under DWARF 4 too.
: "${RUST_DEBUG_FLAGS=-Cdebuginfo=1 -Cdwarf-version=3}"
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

# --cfg fuzzing matches libfuzzer-sys; force-frame-pointers aids ASan backtraces.
# The rlenv PATCH tier prepends `-C debuginfo=2`; we don't fight it. Start RUSTFLAGS
# clean (do NOT inherit the base's clang $RUSTFLAGS/$SANITIZER_FLAGS — rustc rejects -f*).
export RUSTFLAGS="--cfg fuzzing $RUST_SANITIZER $RUST_DEBUG_FLAGS -Cforce-frame-pointers"

# EDIT: the cargo-fuzz crate directory. Use upstream's own fuzz/ when it builds on
# the pinned nightly; otherwise add an ADDITIVE mayhem/fuzz/ crate (leaves upstream
# untouched) and point --fuzz-dir at it.
FUZZ_DIR="mayhem/fuzz"
TRIPLE="x86_64-unknown-linux-gnu"

# Discover every target from the crate's fuzz_targets/ dir (one binary per target).
FUZZ_TARGETS=()
for f in "$FUZZ_DIR"/fuzz_targets/*.rs; do
  FUZZ_TARGETS+=("$(basename "${f%.*}")")
done
[ "${#FUZZ_TARGETS[@]}" -gt 0 ] || { echo "ERROR: no fuzz targets under $FUZZ_DIR/fuzz_targets/" >&2; exit 1; }

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"
echo "targets: ${FUZZ_TARGETS[*]}"

# CRITICAL (DWARF-3 contract): a prior DWARF-5 build could leave cached objects that
# survive incremental recompiles. Wipe the cargo-fuzz output dir so every object is
# recompiled clean under the DWARF-3 RUSTFLAGS/CFLAGS set above.
rm -rf "$SRC/$FUZZ_DIR/target"

# Use the image's DEFAULT toolchain (the Dockerfile pinned it). A `+toolchain`
# override would make rustup try to install another channel into the locked /opt/rust.
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"    # writable output dir (build runs as uid 2000)
  echo "built /mayhem/$t"
done

# Build the behavioral-oracle test suite (mayhem/oracle) with the project's NORMAL
# flags (NO sanitizer/fuzzing cfg) so mayhem/test.sh only RUNS it. These are
# known-answer tests over the exact decoder path the fuzzer drives.
echo "=== building behavioral oracle tests (mayhem/oracle) ==="
(
  cd "$SRC/mayhem/oracle"
  # Clear the fuzzing/ASan RUSTFLAGS for a clean test build.
  RUSTFLAGS="" cargo test --no-run --release
  # Stash the compiled integration-test binaries where test.sh can find them.
  install -d /mayhem/oracle-tests
  # Copy the compiled integration-test binary (skip its .d depfile). The hash suffix
  # varies, so glob and pick the one executable ELF.
  found=""
  for b in target/release/deps/decode_kat-*; do
    if [ -f "$b" ] && [ -x "$b" ]; then
      cp "$b" /mayhem/oracle-tests/decode_kat
      found=1
    fi
  done
  [ -n "$found" ] || { echo "ERROR: no decode_kat test binary produced" >&2; exit 1; }
)
[ -x /mayhem/oracle-tests/decode_kat ] || { echo "ERROR: oracle test binary not built" >&2; exit 1; }
ls -l /mayhem/oracle-tests/

echo "build.sh complete"
