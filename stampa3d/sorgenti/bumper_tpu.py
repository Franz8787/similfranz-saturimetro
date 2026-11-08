# similFranz Saturimetro — bumper in TPU (stile guscio protettivo da saturimetro palmare)
# Si appoggia alle misure di saturimetro_guscio.py (corpo cornice + scocca). Stampa: TPU 95A, dorso sul piatto,
# senza supporti. Si infila tirando il TPU sopra il guscio montato.
#   - pareti 2.0 mm, angoli rinforzati (+0.9 mm) per assorbire le cadute
#   - bordino sul frontale (copre lo smusso + 1 mm); dorso pieno da 1.2 mm (v2)
#   - aperture con 1 mm di margine attorno alle conche dei tasti (volume, accensione), alla sede della spina,
#     al bocchettone del cavo sonda (fessura aperta: si monta con la sonda già attaccata); finestrella sul fianco destro per la scritta incisa
#   - righine antiscivolo sui fianchi, nella parte bassa
import math, os, sys, importlib
import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    os.getcwd()
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import saturimetro_guscio as g
importlib.reload(g)

VERSION = "v6"
T = 2.0            # parete
CORNER = 0.9       # rinforzo agli angoli
LIP_F = 2.5        # quanto il bordino copre il frontale (smusso 1.5 + 1 mm)
LIP_B = 3.0        # (solo con BACK_OPEN) quanto il bordino copre il dorso
BACK_OPEN = False  # v2: dorso pieno, più protettivo e più rigido (si infila dal frontale come una cover)
LIP_T = 1.2        # spessore dei bordini
ROUND = 1.6        # arrotondamento (a 45°) degli spigoli esterni
CLR = 0.05         # gioco sul corpo (il TPU si tende: aderisce comunque)
MARGIN = 1.0       # margine attorno alle aperture del guscio
GRIP_N, GRIP_W, GRIP_D, GRIP_STEP = 6, 1.2, 0.6, 3.0   # righine antiscivolo
COLOR = (0.05, 0.22, 0.70)   # blu (rosso: 0.78, 0.07, 0.08)

OW, OL, R, F, ZB, CH = g.OW, g.OL, g.OUT_R, g.F, g.ZB, g.CH
ZF = LIP_T                     # faccia del bordino frontale
ZK = ZB - LIP_T                # faccia del bordino posteriore (sul piatto)
OUT_DIR = os.path.join(os.path.dirname(HERE), "stl")

# aperture misurate sul guscio v4 (ray-cast sulle mesh reali)
VOL_Y = (8.5, 41.5)           # conca volume sul fianco sinistro, aperta fino a z -8
PWR_X = (3.75, 26.75)         # conca accensione sul bordo alto
DOCK_X = (-19.0, 18.75)       # sede spina sul bordo basso, aperta fino a z -9
NOSE_X = (-22.0, -10.0)       # bocchettone del cavo (scocca), z -18 .. -10.3
TEXT_Y = (-13.7, 13.7)        # scritta incisa sul fianco destro, z -8.1 .. -3.4
TEXT_Z = (-8.1, -3.4)
NOSE_TOP = -10.3              # faccia del naso verso il frontale
NOSE_TIP = 69.75              # punta del naso (uscita del cavo)
COLLAR_T = 1.2                # spessore delle alette del colletto
COLLAR_GAP = 5.0              # fessura fra le alette (il naso è largo 12: 3.5 mm di aletta per lato)
COLLAR_TIP = 1.5              # il colletto si ferma 1.5 mm prima della punta (il cavo esce libero)


def body_loops(w, l, r, c):
    """profilo del corpo (cornice + scocca) allargato di c: smussi 45° davanti e dietro."""
    return [(g.rr_loop(w - 2 * CH + 2 * c, l - 2 * CH + 2 * c, r - CH + c), c),
            (g.rr_loop(w + 2 * c, l + 2 * c, r + c), -CH),
            (g.rr_loop(w + 2 * c, l + 2 * c, r + c), ZB + CH),
            (g.rr_loop(w - 2 * CH + 2 * c, l - 2 * CH + 2 * c, r - CH + c), ZB - c)]


def outer_loops(pts_fn):
    """profilo esterno arrotondato a 45°: pts_fn(inset) -> punti 2D."""
    return [(pts_fn(ROUND), ZF), (pts_fn(0), ZF - ROUND), (pts_fn(0), ZK + ROUND), (pts_fn(ROUND), ZK)]


def stadium_cut(c, along, s0, s1, z0, z1, u0, u1, r=None):
    """apertura sagomata: nel piano (s, z) un rettangolo con angoli raggiati, estruso lungo u (attraverso la parete)."""
    w, h = s1 - s0, z1 - z0
    r = min(w, h) / 2 - 0.01 if r is None else r
    pts = g.rr_loop(w, h, r, 10, dx=(s0 + s1) / 2, dy=(z0 + z1) / 2)
    if along == "y":     # parete laterale (piano y-z), estrusione lungo x
        return g.prism("t", pts, u0, u1, c, g.M_ALONG_X)
    return g.prism("t", pts, u0, u1, c, g.M_ALONG_Y)      # parete alta/bassa (piano x-z), estrusione lungo y


def build(c):
    W, L = OW + 2 * T, OL + 2 * T
    body = g.hull("bumper_tpu", outer_loops(lambda i: g.rr_loop(W - 2 * i, L - 2 * i, R + T - i)), c)
    # angoli rinforzati
    adds = []
    for sx in (1, -1):
        for sy in (1, -1):
            cx, cy = sx * (OW / 2 - R), sy * (OL / 2 - R)
            rc = R + T + CORNER
            adds.append(g.hull("t", outer_loops(lambda i, cx=cx, cy=cy: [(cx + x, cy + y) for x, y in g.circle(rc - i, 48)]), c))
    g.boolean(body, adds, "UNION")
    cuts = [g.hull("t", body_loops(OW, OL, R, CLR), c)]                                   # il saturimetro
    cuts.append(g.prism("t", g.rr_loop(OW - 2 * LIP_F, OL - 2 * LIP_F, R - LIP_F), -1.0, ZF + 1, c))     # fronte
    if BACK_OPEN:
        cuts.append(g.prism("t", g.rr_loop(OW - 2 * LIP_B, OL - 2 * LIP_B, R - LIP_B), ZK - 1, ZB + 1.0, c))  # dorso
    m, out = MARGIN, 10.0
    xo, yo = OW / 2, OL / 2
    # conca volume (fianco sinistro): dal fondo della conca fino al frontale, bordino compreso
    cuts.append(stadium_cut(c, "y", VOL_Y[0] - m, VOL_Y[1] + m, -8.0 - m, ZF + out, -xo - out, -xo + LIP_F + 4, r=3.0))
    # conca accensione (bordo alto)
    cuts.append(stadium_cut(c, "x", PWR_X[0] - m, PWR_X[1] + m, -8.0 - m, ZF + out, yo - LIP_F - 4, yo + out, r=3.0))
    # sede della spina (bordo basso)
    cuts.append(stadium_cut(c, "x", DOCK_X[0] - m, DOCK_X[1] + m, -9.0 - m, ZF + out, -yo - out, -yo + LIP_F + 4, r=3.0))
    # bocchettone del cavo sonda: fessura aperta verso il frontale (nessun ponte): il saturimetro, con la sonda già
    # montata, si appoggia dentro dall'alto e il naso si posa sul dorso pieno del bumper
    cuts.append(stadium_cut(c, "x", NOSE_X[0] - m, NOSE_X[1] + m, ZB, ZF + out, yo - LIP_F - 1.5, yo + out, r=0.6))   # anche il bordino frontale
    # finestrella per la scritta incisa (fianco destro)
    cuts.append(stadium_cut(c, "y", TEXT_Y[0] - 2.3, TEXT_Y[1] + 2.3, TEXT_Z[0] - 0.8, TEXT_Z[1] + 0.8, xo - 1, xo + out))
    # righine antiscivolo: solchi sui fianchi, parte bassa (lontano da tasti, scritta e angoli)
    for sx in (1, -1):
        for k in range(GRIP_N):
            yc = -50.0 + k * GRIP_STEP
            x_in = sx * (xo + T - GRIP_D)
            cuts.append(stadium_cut(c, "y", yc - GRIP_W / 2, yc + GRIP_W / 2, ZB + 2.0, -2.5,
                                    min(x_in, sx * (xo + out)), max(x_in, sx * (xo + out)), r=GRIP_W / 2 - 0.01))
    g.boolean(body, cuts, "DIFFERENCE")
    # colletto attorno al bocchettone: fianchi aderenti e due alette sopra il naso con una fessura al centro.
    # Tiene uniti i lembi della fessura (il bumper non si slabbra) e trattiene il naso a scatto, senza chiuderlo.
    nx0, nx1 = NOSE_X
    zc0, zc1 = ZK, NOSE_TOP + COLLAR_T
    collar = stadium_cut(c, "x", nx0 - T, nx1 + T, zc0, zc1, OL / 2 - 3.0, NOSE_TIP - COLLAR_TIP, r=2.0)
    g.boolean(body, collar, "UNION")
    xm, hg = (nx0 + nx1) / 2, COLLAR_GAP / 2
    cuts2 = [g.hull("t", body_loops(OW, OL, R, CLR), c),
             g.box("t", nx0 - CLR, nx1 + CLR, OL / 2 - 4.0, NOSE_TIP + 5, ZB, NOSE_TOP + CLR, c),          # il naso
             g.box("t", xm - hg, xm + hg, OL / 2 - 4.0, NOSE_TIP + 5, ZB, ZF + 10, c),                      # fessura centrale
             g.prism("t", [(xm - hg, NOSE_TOP + CLR), (xm + hg, NOSE_TOP + CLR), (xm + hg + COLLAR_T, NOSE_TOP + COLLAR_T + CLR),
                           (xm - hg - COLLAR_T, NOSE_TOP + COLLAR_T + CLR)],
                     OL / 2 - 1.0, NOSE_TIP + 5, c, g.M_ALONG_Y),                                            # invito a 45° sulle alette
             g.box("t", nx0 - m, nx1 + m, OL / 2 - LIP_F - 1.5, OL / 2 + 0.01, NOSE_TOP + COLLAR_T, ZF + 10, c)]  # niente ponte sul frontale
    g.boolean(body, cuts2, "DIFFERENCE")
    # bordino frontale e parete alta richiusi anche sopra il naso: resta solo la fessura centrale (continua con quella
    # delle alette), così il bumper abbraccia tutto il contorno e si apre quanto basta per far scattare il naso
    patch = g.hull("t", outer_loops(lambda i: g.rr_loop(W - 2 * i, L - 2 * i, R + T - i)), c)
    g.boolean(patch, g.box("t", nx0 - m - 0.01, nx1 + m + 0.01, OL / 2 - LIP_F - 3, OL / 2 + T + 3,
                           NOSE_TOP + COLLAR_T - 0.4, ZF + 1, c), "INTERSECT")
    g.boolean(body, patch, "UNION")
    y0 = OL / 2 - LIP_F - 3
    cuts3 = [g.hull("t", body_loops(OW, OL, R, CLR), c),
             g.prism("t", g.rr_loop(OW - 2 * LIP_F, OL - 2 * LIP_F, R - LIP_F), -1.0, ZF + 1, c),
             g.box("t", nx0 - CLR, nx1 + CLR, OL / 2 - 4.0, NOSE_TIP + 5, ZB, NOSE_TOP + CLR, c),
             g.box("t", xm - hg, xm + hg, y0, NOSE_TIP + 5, ZB, ZF + 10, c),
             g.prism("t", [(xm - hg, NOSE_TOP + CLR), (xm + hg, NOSE_TOP + CLR), (xm + hg + COLLAR_T, NOSE_TOP + COLLAR_T + CLR),
                           (xm - hg - COLLAR_T, NOSE_TOP + COLLAR_T + CLR)],
                     OL / 2 - 1.0, NOSE_TIP + 5, c, g.M_ALONG_Y)]                                   # invito solo sulle alette
    g.boolean(body, cuts3, "DIFFERENCE")
    return body


def run_live(export=True):
    """nella scena aperta: saturimetro tutto bianco, bumper nella collezione similFranz_Bumper, STL esportato."""
    c = g.get_coll("similFranz_Bumper")
    white = g.material("SF_bianco", (0.85, 0.86, 0.88), 0.45)
    for name in ("scocca", "cornice", "cornice_v3", "cornice_v4"):
        ob = bpy.data.objects.get(name)
        if ob and ob.type == "MESH":
            ob.data.materials.clear(); ob.data.materials.append(white)
    b = build(c)
    b.data.materials.clear(); b.data.materials.append(g.material("SF_tpu", COLOR, 0.7))
    bad, vol = g.check(b)
    M = Matrix.Translation((0, 0, -ZK))                       # dorso sul piatto
    bb = [M @ v.co for v in b.data.vertices]
    size = [round(max(p[i] for p in bb) - min(p[i] for p in bb), 1) for i in range(3)]
    path = os.path.join(OUT_DIR, f"saturimetro_bumper_tpu_{VERSION}.stl")
    if export:
        g.write_stl([b], path, M)
    return dict(non_manifold_edges=bad, volume_cm3=round(vol / 1000, 2), print_size_mm=size, stl=path if export else None)


if __name__ == "__main__":
    print(run_live())
