#!/bin/bash
# Compila SimulaFranz_Saturimetro per iPod touch 4 (armv7, iOS >= 6.0) senza Xcode:
# Command Line Tools (clang + ld) + iPhoneOS9.3.sdk (vedi docs/sviluppo.md) + ldid.
# Nota ARC: con target iOS 6 clang vorrebbe libarclite (rimossa da Xcode 14.3): basta NON passare
# -fobjc-arc al link, i simboli ARC sono già nel runtime di iOS 6.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SIMLAB_SDK:-$ROOT/sdk/iPhoneOS9.3.sdk}"          # vedi docs/sviluppo.md: l'SDK non e' incluso (e' materiale Apple)
BUILD="$ROOT/build"; APP="$BUILD/SimulaFranz_Saturimetro.app"; MIN_IOS=6.0
die() { echo "ERRORE: $*" >&2; exit 1; }
[ -d "$SDK" ] || die "SDK non trovato in $SDK"
command -v xcrun >/dev/null || die "Command Line Tools assenti"
command -v ldid >/dev/null || die "ldid assente (brew install ldid)"
[ -f "$ROOT/assets/Icon.png" ] || "$ROOT/scripts/make-assets.sh"

# -Werror=unguarded-availability: qualsiasi API più recente di iOS 6.0 è un errore di compilazione
CFLAGS=(-target armv7-apple-ios$MIN_IOS -isysroot "$SDK" -fobjc-arc -Os -g0
        -Wall -Wno-unused-parameter -Wno-deprecated-declarations -Werror=unguarded-availability
        -Werror=objc-method-access -Werror=incompatible-pointer-types -Werror=implicit-function-declaration -I"$ROOT/src")
FRAMEWORKS=(-framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore
            -framework AVFoundation -framework AudioToolbox -framework CoreFoundation)
rm -rf "$BUILD/obj" "$APP"; mkdir -p "$BUILD/obj" "$APP"
echo "== compilazione ($(xcrun clang --version | head -1))"
for f in "$ROOT"/src/*.m; do echo "   $(basename "$f")"; xcrun clang "${CFLAGS[@]}" -c "$f" -o "$BUILD/obj/$(basename "${f%.m}").o"; done
echo "== link"
xcrun clang -target armv7-apple-ios$MIN_IOS -isysroot "$SDK" "${FRAMEWORKS[@]}" "$BUILD"/obj/*.o -o "$APP/SimulaFranz_Saturimetro" 2>&1 | grep -v "built for iOS Simulator" || true
[ -f "$APP/SimulaFranz_Saturimetro" ] || die "link fallito"
echo "== bundle"
plutil -convert binary1 -o "$APP/Info.plist" "$ROOT/assets/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"
cp "$ROOT"/assets/*.png "$APP/"
cp -R "$ROOT/assets/Settings.bundle" "$APP/"
mkdir -p "$APP/www" && cp "$ROOT"/www/index.html "$APP/www/"      # console web dell'uso autonomo
echo "== firma ldid"
ldid -S "$APP/SimulaFranz_Saturimetro"
echo "== verifica"
lipo -info "$APP/SimulaFranz_Saturimetro" | grep -q armv7 || die "binario non armv7"
otool -l "$APP/SimulaFranz_Saturimetro" | awk '/LC_VERSION_MIN_IPHONEOS/{f=1} f&&/version/{print "   iOS minimo:", $2; exit}'
echo "OK: $APP"
