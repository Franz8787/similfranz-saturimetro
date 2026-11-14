#!/bin/bash
# Compila ed esegue su macOS i test di logica (stato, allarmi, menu, battiti, stato locale, server interno)
# e costruisce il server di riferimento build/mac/mac-oxi-server (console web senza iPod).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$ROOT/build/mac"; mkdir -p "$OUT"
FILES=("$ROOT/src/OxiState.m" "$ROOT/src/OxiEngine.m" "$ROOT/src/OxiLocalState.m" "$ROOT/src/LocalHTTPServer.m" "$ROOT/src/OxiServer.m" "$ROOT/src/OxiUpdate.m")
xcrun clang -fobjc-arc -Wall -Wno-unused-parameter -I"$ROOT/src" -framework Foundation -lz "${FILES[@]}" "$ROOT/tests/run-tests.m" -o "$OUT/run-tests"
xcrun clang -fobjc-arc -Wall -Wno-unused-parameter -I"$ROOT/src" -framework Foundation -lz "${FILES[@]}" "$ROOT/tests/mac-oxi-server.m" -o "$OUT/mac-oxi-server"
TEST_DEB="$(ls -t "$ROOT"/dist/*.deb 2>/dev/null | head -1)" "$OUT/run-tests"
