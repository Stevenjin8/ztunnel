#!/usr/bin/env bash
# shellcheck disable=SC2046,SC2086

# Copyright Istio Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -xe

ARTIFACTS="${ARTIFACTS:-out/coverage}"
output_dir=$ARTIFACTS/report
# Where to store merged coverage file 
profdata=out/coverage/ztunnel.profdata
# Where to store intermediate *.profraw files
profiles=out/coverage/profiles

export LLVM_PROFILE_FILE="$profiles/profile_%m_%p.profraw"
# Enable coverage
export RUSTFLAGS="-C instrument-coverage"
export RUST_BACKTRACE=1
RUSTUP_DEFAULT_TOOLCHAIN="$(rustup show active-toolchain | awk '{print $1}')"
RUSTUP_LLVM_BIN_PATH="${HOME}/.rustup/toolchains/${RUSTUP_DEFAULT_TOOLCHAIN}/lib/rustlib/$(arch)-unknown-linux-gnu/bin"

# Clean directory
rm -rf "$profdata" "$profiles"
mkdir -p "$profiles"

echo "Running tests"
cargo test --benches --tests --bins $FEATURES

# Merge profraw data
echo "Merging profraw files in $profiles to $profdata"
${RUSTUP_LLVM_BIN_PATH}/llvm-profdata merge -sparse $(find "$profiles" -name '*.profraw') -o $profdata

# Taken from 
# https://doc.rust-lang.org/rustc/instrument-coverage.html#tips-for-listing-the-binaries-automatically
test_bins=$(cargo test --benches --tests --bins --no-run --message-format=json $FEATURES \
| jq -r "select(.profile.test == true) | .filenames[]" \
| grep -v dSYM -)

objs=""
for file in $test_bins
do
    objs="$objs $(printf "%s %s " -object "$file")"
done
echo $objs

echo "Publishing coverage report to $output_dir"

${RUSTUP_LLVM_BIN_PATH}/llvm-cov show \
    -instr-profile="$profdata" \
    $objs \
    -Xdemangler=rustfilt \
    -format=html \
    -sources=$(find src -name '*.rs') \
    -output-dir="$output_dir"
