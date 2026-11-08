#!/bin/bash
# Crea dist/it.simulafranz.saturimetro_<ver>_iphoneos-arm.deb (app in /Applications, root:wheel). Non serve dpkg sul Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; APP="$ROOT/build/SimulaFranz_Saturimetro.app"
[ -x "$APP/SimulaFranz_Saturimetro" ] || { echo "ERRORE: eseguire prima scripts/build.sh" >&2; exit 1; }
mkdir -p "$ROOT/dist"
python3 - "$ROOT" <<'PY'
import io, os, sys, tarfile, time, gzip
root = sys.argv[1]; app = os.path.join(root, "build", "SimulaFranz_Saturimetro.app")
control = open(os.path.join(root, "control")).read().strip() + "\n"
fields = dict(l.split(": ", 1) for l in control.splitlines() if ": " in l)
size = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(app) for f in fs) // 1024 + 1
control += f"Installed-Size: {size}\n"; now = int(time.time())
def tar_gz(add):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t: add(t)
    return gzip.compress(buf.getvalue(), 9, mtime=now)
def info(name, mode, size=0, isdir=False):
    ti = tarfile.TarInfo(name); ti.mode = mode; ti.size = size; ti.mtime = now; ti.uid = ti.gid = 0; ti.uname = "root"; ti.gname = "wheel"
    if isdir: ti.type = tarfile.DIRTYPE
    return ti
POST = "#!/bin/sh\nif [ -x /usr/bin/uicache ]; then cd / && (su mobile -c /usr/bin/uicache || /usr/bin/uicache) >/dev/null 2>&1 || true; fi\nexit 0\n"
def add_control(t):
    for name, data, mode in [("./control", control, 0o644), ("./postinst", POST, 0o755), ("./postrm", POST, 0o755)]:
        b = data.encode(); t.addfile(info(name, mode, len(b)), io.BytesIO(b))
def add_data(t):
    for d in ["./", "./Applications/"]: t.addfile(info(d, 0o755, isdir=True))
    base = "./Applications/SimulaFranz_Saturimetro.app"
    for dirpath, dirs, files in os.walk(app):
        dirs.sort(); rel = os.path.relpath(dirpath, app); dest = base if rel == "." else f"{base}/{rel}"
        t.addfile(info(dest + "/", 0o755, isdir=True))
        for f in sorted(files):
            p = os.path.join(dirpath, f); mode = 0o755 if f == "SimulaFranz_Saturimetro" and rel == "." else 0o644
            with open(p, "rb") as fh: t.addfile(info(f"{dest}/{f}", mode, os.path.getsize(p)), fh)
members = [("debian-binary", b"2.0\n"), ("control.tar.gz", tar_gz(add_control)), ("data.tar.gz", tar_gz(add_data))]
out = io.BytesIO(); out.write(b"!<arch>\n")
for name, data in members:
    hdr = f"{name:<16}{now:<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n".encode(); assert len(hdr) == 60
    out.write(hdr); out.write(data)
    if len(data) % 2: out.write(b"\n")
path = os.path.join(root, "dist", f"{fields['Package']}_{fields['Version']}_{fields['Architecture']}.deb")
open(path, "wb").write(out.getvalue()); print(path)
PY
