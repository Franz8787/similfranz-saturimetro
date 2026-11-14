#!/bin/bash
# Prepara l'SDK iOS per compilare similFranz Saturimetro (armv7, iOS 6) SENZA Xcode. Lo usa anche GitHub Actions.
#
# Fonte: repository ufficiale theos/sdks (commit fissato sotto).
# Licenza SDK: Xcode and Apple SDKs Agreement (LICENSE.md del repository).
#
# Perché le patch: i file .tbd (tbd v1) di iPhoneOS9.3.sdk sono incompleti
# (mancano p.es. _memset, _strcmp, NSNetService) e il linker moderno (ld-1230)
# non tollera re-export mancanti. Lo script:
#   1) aggiunge uno stub liblaunch.tbd (re-export dichiarato in libSystem.tbd)
#   2) per le librerie usate dall'app, integra nel .tbd 9.3 i simboli presenti
#      nel corrispondente .tbd di iPhoneOS10.3.sdk (stesso repo/commit).
# Sicurezza: gli HEADER restano quelli 9.3 e build.sh blocca ogni API più recente di iOS 6
# (-Werror=unguarded-availability); i simboli aggiunti servono solo al linker.
# Uso: app/scripts/setup-sdk.sh   poi   SIMLAB_SDK=app/sdk/theos-sdks/iPhoneOS9.3.sdk app/scripts/build.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TC="${SIMLAB_TOOLCHAIN:-$HERE/sdk}"          # di serie: app/sdk/ (escluso da git)
REPO=https://github.com/theos/sdks.git
COMMIT=0222fd5413cf4b9af096f37b4621afa2688572f7
RAW=https://raw.githubusercontent.com/theos/sdks/$COMMIT/iPhoneOS10.3.sdk
SDK="$TC/theos-sdks/iPhoneOS9.3.sdk"
TBDS=(
  usr/lib/system/libsystem_c.tbd
  usr/lib/system/libsystem_platform.tbd
  usr/lib/system/libsystem_kernel.tbd
  usr/lib/system/libsystem_info.tbd
  usr/lib/system/libsystem_m.tbd
  usr/lib/system/libdispatch.tbd
  usr/lib/libobjc.tbd
  System/Library/Frameworks/Foundation.framework/Foundation.tbd
  System/Library/Frameworks/CoreFoundation.framework/CoreFoundation.tbd
  System/Library/Frameworks/UIKit.framework/UIKit.tbd
  System/Library/Frameworks/CoreGraphics.framework/CoreGraphics.tbd
  System/Library/Frameworks/QuartzCore.framework/QuartzCore.tbd
  System/Library/Frameworks/AVFoundation.framework/AVFoundation.tbd
)

mkdir -p "$TC"
if [ ! -d "$TC/theos-sdks/.git" ]; then
  git clone --filter=blob:none --no-checkout "$REPO" "$TC/theos-sdks"
fi
cd "$TC/theos-sdks"
git sparse-checkout set iPhoneOS9.3.sdk
git checkout -q "$COMMIT"
git checkout -q -- iPhoneOS9.3.sdk          # riparte sempre dai file originali
echo "SDK base: theos/sdks@$COMMIT iPhoneOS9.3.sdk"

cat > "$SDK/usr/lib/system/liblaunch.tbd" <<'TBD'
---
archs:                 [ armv7, armv7s, arm64, i386, x86_64 ]
platform:              ios
install-name:          /usr/lib/system/liblaunch.dylib
current-version:       765.50.8
compatibility-version: 1
exports:
  - archs:             [ armv7, armv7s, arm64, i386, x86_64 ]
...
TBD
echo "patch: liblaunch.tbd (stub)"

REF="$TC/sdk10.3-tbd"; mkdir -p "$REF"
for t in "${TBDS[@]}"; do
  dst="$REF/$t"; mkdir -p "$(dirname "$dst")"
  [ -s "$dst" ] || curl -fsSL "$RAW/$t" -o "$dst"
  python3 - "$SDK/$t" "$dst" <<'PY'
import re, sys
old_p, ref_p = sys.argv[1], sys.argv[2]
old, ref = open(old_p).read(), open(ref_p).read()
def collect(text, key):
    out = set()
    for m in re.finditer(r'^\s*' + key + r':\s*\[(.*?)\]', text, re.S | re.M):
        out |= {s.strip().strip("'\"") for s in m.group(1).replace("\n", " ").split(",") if s.strip()}
    return out
added = []
for key in ("symbols", "objc-classes", "objc-ivars", "weak-def-symbols"):
    miss = sorted(collect(ref, key) - collect(old, key))
    if miss:
        q = ", ".join("'" + s + "'" if "$" in s else s for s in miss)
        added.append(f"    {key}: [ {q} ]\n")
if added:
    block = "  - archs:              [ armv7, armv7s, arm64 ]  # SIMLAB-PATCH (simboli da 10.3)\n" + "".join(added)
    i = old.rstrip().rfind("\n...")
    assert i > 0, "formato tbd inatteso: " + old_p
    open(old_p, "w").write(old[:i+1] + block + old[i+1:])
n = sum(len(l.split(",")) for l in added)
print(f"patch: {old_p.split('iPhoneOS9.3.sdk/')[1]}: +{n} simboli" if added else f"ok: {old_p.split('iPhoneOS9.3.sdk/')[1]}")
PY
done
echo "SDK pronto: $SDK"
