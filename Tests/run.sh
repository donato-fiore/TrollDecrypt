#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Werror -framework Foundation -IDecryption \
    Decryption/MachOInspection.m Decryption/MachORebuilder.m Decryption/MemoryUtilities.m \
    Decryption/DecryptionOutput.m Tests/FatDecryptionTests.m -o "$temporary/fat-tests"
"$temporary/fat-tests"
