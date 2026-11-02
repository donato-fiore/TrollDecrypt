#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -framework Foundation -IDecryption \
    Decryption/MachOInspection.m Decryption/LaunchdResponse.m Decryption/DecryptionOutput.m Tests/InspectionTests.m -o "$temporary/inspection-tests"
"$temporary/inspection-tests"
