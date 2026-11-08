# SimulaFranz_Saturimetro — guscio stile saturimetro palmare per iPod touch 4a gen. (MC540BT/A, A1367)
# Parametrico: cambia le misure qui sotto e rilancia lo script in Blender (anche headless:
#   /Applications/Blender.app/Contents/MacOS/Blender --background --python saturimetro_guscio.py).
# Unità: 1 BU = 1 mm. Stampa: Bambu Lab A1, PLA o PETG, senza supporti.
#
# Pezzi:
#   cornice  (frontale)   -> stampata a faccia in giù; finestra display, foro Home,
#                            scassi a tasca (aperti sul frontale, svasati, chiusi ai lati) per tasti e spina
#   scocca   (posteriore) -> stampata col dorso sul piatto; costole sagomate sulla cupola dell'iPod,
#                            vano cavo sonda, bocchettone in alto, fermacavo
# Viteria: 4 inserti filettati a caldo M2 nelle colonne d'angolo della cornice, 4 viti M2x12 dal retro.
# I tasti NON hanno pistoncini: finestre a filo del tasto, raggiungibili col polpastrello dentro la gola.
#
# Quote iPod touch 4 dal disegno Apple "Case Design Guidelines" 2014-10-16, fig. 2-28 (pag. 44):
#   corpo 110.9 x 58.8 x 7.2, raggio angoli 8.5; frontale piatto con fascia laterale ~1.8 mm, dorso a cupola
#   (7.2 mm a ~10.5 mm dai lati lunghi e ~13 mm dalle estremità; profilo misurato sulle viste laterali)
#   display 74.9 x 49.9 centrato; Home Ø10.2 a 9.3 dal bordo basso
#   accensione: bordo alto, 9.2..19.2 dal bordo destro, 2.0 alto, sporge 0.5 (a 0.9..2.9 dal vetro)
#   volume: bordo sinistro, (+) 20.5..29.4 e (-) 31.7..40.6 dal bordo alto, 1.9 alti, sporgono 0.5
#   fondo: altoparlante 9.4..14.4 da sx, dock 30 pin 22.1 centrato (spina con guscio ~28 x 8.5), jack a 9.9 da dx

import bpy, bmesh, math, os, struct
from mathutils import Matrix, Vector

# ---------------------------------------------------------------- parametri
DEV_W, DEV_L, DEV_T, DEV_R = 58.8, 110.9, 7.2, 8.5
DEV_BAND, DEV_DOME_X, DEV_DOME_Y = 1.8, 10.5, 13.0     # profilo del dorso (fascia piatta + cupola parabolica)
SCR_W, SCR_L = 49.9, 74.9
HOME_Y, HOME_D = -(DEV_L / 2 - 9.3), 10.2
POWER_X, POWER_L = DEV_W / 2 - 9.2 - 5.0, 10.0       # centro e lunghezza del tasto (bordo alto, a destra)
VOL_Y0, VOL_Y1 = DEV_L / 2 - 40.6, DEV_L / 2 - 20.5  # fascia dei due tasti volume (bordo sinistro)
BTN_MARG = 2.5          # finestra = tasto + margine per lato
NOTCH_FLARE = 1.5                                    # svaso 45° sull'imbocco degli scassi (dito e spina entrano meglio)
END_WALL = 2.0                                       # paretine che chiudono il corridoio attorno all'iPod ai lati di ogni scasso
POCKET_D = 8.0                                       # tasche dei tasti: fondo a 8 mm dal frontale (tasti a 2.9..4.9): il polpastrello arriva a 0.5 mm
BTN_RELIEF = 0.0                                     # smusso 45° del frontale sopra il tasto (v2: 3 mm); 0 = niente smusso, frontale dritto
GROOVE_FLOOR = 0.8                                   # fondo delle conche spiovente: a filo esterno resta a POCKET_D, sul bordo dell'iPod scende fino a lasciare 0.8 mm
SOFT_R, SOFT_SEG, SOFT_ANG = 0.8, 4, 25.0             # arrotondamento degli spigoli delle conche dei tasti (raggio, segmenti, angolo minimo)
POCKET_M = 1.5                                       # margine oltre il tasto alla quota del tetto; le testate salgono a 45°
DOCK_W = 28.0           # tasca della spina 30 pin nella cornice: connettore 27 x 6.66 mm + 0.5 mm per lato (larghezza sul fondo)
PLUG_T, PLUG_ZC = 6.66, 3.5   # spessore del connettore e posizione del suo centro dal vetro (porta dock dell'iPod)
DOCK_CLR = 0.5          # gioco attorno al connettore nella finestra
DOCK_R_END = 5.0        # raccordo fondo/testate della tasca spina (testate poi dritte: l'iPod appoggia ai lati)
PLUG_OUT = 9.42         # sporgenza del connettore inserito, misurata dal bordo dell'iPod
DOCK_REAR = 3.0         # lo scasso prosegue nella scocca (guscio della spina più spesso dell'iPod)
CHIN = 0.0              # nessun prolungamento sotto l'iPod

CLR = 0.3               # gioco per lato attorno all'iPod
GAP = 4.0               # spazio fra iPod e parete della scocca (ci stanno le colonne delle viti agli angoli)
WALL = 2.0              # pareti
PLATE = 2.0             # frontale davanti al vetro
POCKET_EXTRA = 0.8      # gioco in profondità
REAR = 6.0              # vano dietro l'iPod (cavo sonda, fascette)
BACK = 2.0              # dorso della scocca
CH = 1.5                # smusso spigoli esterni
IR = 5.0                # raggio interno della cavità della scocca (angoli "squadrati": fanno posto alle colonne)
LIP_T, LIP_H, LIP_CLR = 1.4, 2.5, 0.25   # labbro della cornice che entra nella scocca
PANEL_D = 0.0

WIN_W, WIN_L, WIN_R, WIN_CH = SCR_W + 0.6, SCR_L + 0.6, 2.0, 0.8
HOME_HOLE_D, HOME_CH = 11.4, 0.8

COL_R = 3.6             # colonne viti agli angoli (v4: 3.0 -> 3.6, vite spostata 0.6 verso l'esterno: 2.1 mm di plastica piena attorno all'inserto lato iPod)
INS_HOLE, INS_DEPTH = 3.0, 6.0     # sede inserto M2 x 4 x OD 3.2 (kit utente): foro 3.0, 6 mm = 4 inserto + 2 di pozzetto per la plastica che risale
SCREW_HOLE, CB_D, CB_DEPTH = 2.4, 4.6, 1.0   # passaggio M2 e lamatura testa nel dorso
RIB_CLR = 0.2           # gioco fra nervature di centraggio e iPod
CRADLE_Y = (-36.0, 0.0, 36.0)   # costole trasversali del dorso, sagomate sulla cupola (zona piatta: |y| < 42)
CRADLE_T, CRADLE_CLR = 2.4, 0.3  # spessore costole e gioco dalla cupola
TOWER_SETBACK = 2.5   # v3 scocca: la curva delle torrette si ferma 2.5 mm prima del fianco dell'iPod (prima arrivava al fianco, sotto i tasti)
TEXT = "SIM_ilFranz"     # scritta incisa sul fianco destro della cornice (parete verticale in stampa: niente primo strato schiacciato)
TEXT_FONT = "/System/Library/Fonts/Supplemental/DIN Alternate Bold.ttf"   # bastone grassetto: tratti ~0.9 mm a 4 mm di maiuscola
TEXT_CAP, TEXT_DEPTH = 4.0, 0.6  # altezza maiuscole e profondità (3 strati di parete)
CRUSH_W, CRUSH_INT = 1.2, 0.25   # 'crush ribs' sulle costole: listelli da 0.8 mm che interferiscono 0.25 mm con il dorso
CRUSH_X = (-17.0, 0.0, 17.0)     # (si schiacciano al montaggio: l'iPod resta premuto contro il frontale, niente gioco)

CABLE_X, CABLE_D = -16.0, 4.0     # uscita cavo sonda sul bordo alto: cavo misurato Ø3.57 + 0.2 mm di gioco per lato
NOSE_W, NOSE_L = 12.0, 8.0        # bocchettone esterno
TIE_Y = 48.0                      # ponticelli per fascetta (ferma-cavo) nel vano posteriore (oltre la torretta del volume)

VERSION = "v4"
HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else \
    os.getcwd()
OUT_DIR = os.path.join(os.path.dirname(HERE), "stl")
COLL, REF = "SimulaFranz_Saturimetro", "SimulaFranz_Riferimento"

# ---------------------------------------------------------------- derivate
# l'iPod sta nell'origine; il corpo e' allungato in basso dal mento, quindi il suo centro e' a YB
IW, IL = DEV_W + 2 * (CLR + GAP), DEV_L + 2 * (CLR + GAP)       # cavità scocca (attorno all'iPod)
IWF, ILF, IRF = IW - 2 * LIP_T, IL - 2 * LIP_T, IR - LIP_T        # cavità cornice (parete più spessa: diventa il labbro)
OW, OL = IW + 2 * WALL, IL + 2 * WALL + CHIN
YB = -CHIN / 2
Y_TOP, Y_BOT = OL / 2 + YB, -OL / 2 + YB                           # facce alta e bassa del corpo
OUT_R = IR + WALL
F = PLATE + DEV_T + POCKET_EXTRA                                   # profondità cornice = piano di battuta
ZB = -(F + REAR + BACK)                                            # dorso
FLOOR = ZB + BACK
DOCK_ZT = -(PLATE + PLUG_ZC - PLUG_T / 2 - DOCK_CLR)   # bordo alto della finestra (resta il frontale sopra)
DOCK_Z0 = -(PLATE + PLUG_ZC + PLUG_T / 2 + DOCK_CLR)   # bordo basso (resta la cornice sotto, la scocca non si tocca)                                     # fondo dello scasso spina
ZC = -F - 4.3                                                      # asse del foro cavo
Z_DEV = -(PLATE + DEV_T / 2)                                       # mezzeria dell'iPod (asse del tunnel spina)
_d = DEV_R + CLR + 0.3 + COL_R
SCREWS = [(sx * (DEV_W / 2 - DEV_R + _d / math.sqrt(2)), sy * (DEV_L / 2 - DEV_R + _d / math.sqrt(2)))
          for sx in (1, -1) for sy in (1, -1)]
CHIN_SCREWS = [(sx * 24.0, -IL / 2 - CHIN / 2) for sx in (1, -1)] if CHIN >= 10 else []
ALL_SCREWS = SCREWS + CHIN_SCREWS


# ---------------------------------------------------------------- utilità
def rr_loop(w, h, r, seg=12, dx=0.0, dy=0.0):
    if dx or dy:
        return [(x + dx, y + dy) for x, y in rr_loop(w, h, r, seg)]
    r = max(min(r, w / 2 - 0.01, h / 2 - 0.01), 0.01)
    cx, cy = w / 2 - r, h / 2 - r
    pts = []
    for sx, sy, a0 in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        for i in range(seg + 1):
            a = math.radians(a0 + 90 * i / seg)
            pts.append((sx * cx + r * math.cos(a), sy * cy + r * math.sin(a)))
    return pts


def circle(r, seg=40):
    return [(r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg)) for i in range(seg)]


def rect(x0, x1, y0, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def new_obj(name, bm, coll):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def hull(name, loops, coll, M=None, pts3=()):
    """loops: [(pts2d, z), ...] (+ punti 3D liberi) -> solido convesso."""
    bm = bmesh.new()
    for pts, z in loops:
        for x, y in pts:
            bm.verts.new((x, y, z))
    for p in pts3:
        bm.verts.new(p)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    junk = list({g for g in res["geom_interior"] + res["geom_unused"] if isinstance(g, bmesh.types.BMVert)})
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="VERTS")
    bmesh.ops.dissolve_limit(bm, angle_limit=0.0005, verts=bm.verts[:], edges=bm.edges[:])
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return new_obj(name, bm, coll)


def prism(name, pts, z0, z1, coll, M=None):
    return hull(name, [(pts, z0), (pts, z1)], coll, M)


def cyl(name, p0, p1, r, coll, seg=40):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    M = Matrix.Translation(p0) @ Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    return hull(name, [(circle(r, seg), 0.0), (circle(r, seg), d.length)], coll, M)


def capsule(name, p0, p1, r, coll):
    """capsula (cilindro con estremità sferiche) fra p0 e p1: usata come fresa per le gole dei tasti."""
    pts = []
    for p in (Vector(p0), Vector(p1)):
        for i in range(1, 12):
            th = math.pi * i / 12
            z, rr = r * math.cos(th), r * math.sin(th)
            pts += [p + Vector((rr * math.cos(a), rr * math.sin(a), z)) for a in [2 * math.pi * k / 24 for k in range(24)]]
        pts += [p + Vector((0, 0, r)), p + Vector((0, 0, -r))]
    return hull(name, [], coll, pts3=pts)


def box(name, x0, x1, y0, y1, z0, z1, coll):
    return prism(name, rect(x0, x1, y0, y1), z0, z1, coll)


def bake(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=bm.edges[:])
    bm.to_mesh(me); bm.free()
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def boolean(target, tools, op):
    if not isinstance(tools, (list, tuple)):
        tools = [tools]
    for tool in tools:
        m = target.modifiers.new("bool", "BOOLEAN")
        m.operation = op
        m.object = tool
        try:
            m.solver = "MANIFOLD"
        except TypeError:
            m.solver = "EXACT"
        bake(target)
        me = tool.data
        bpy.data.objects.remove(tool)
        bpy.data.meshes.remove(me)


def material(name, rgb, rough=0.5):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1)
        bsdf.inputs["Roughness"].default_value = rough
    mat.diffuse_color = (*rgb, 1)
    return mat


def check(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bad = sum(1 for e in bm.edges if not e.is_manifold)
    vol = bm.calc_volume()
    bm.free()
    return bad, vol


def write_stl(obs, path, M):
    tris = []
    for ob in obs:
        me = ob.data
        me.calc_loop_triangles()
        tris += [[M @ me.vertices[i].co for i in t.vertices] for t in me.loop_triangles]
    with open(path, "wb") as f:
        f.write(b"SimulaFranz saturimetro".ljust(80, b" "))
        f.write(struct.pack("<I", len(tris)))
        for v in tris:
            n = (v[1] - v[0]).cross(v[2] - v[0])
            if n.length > 0:
                n.normalize()
            f.write(struct.pack("<12fH", n.x, n.y, n.z, *v[0], *v[1], *v[2], 0))


# matrici per estrudere sezioni lungo y (loop nel piano x-z) e lungo x (loop nel piano y-z)
M_ALONG_Y = Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
M_ALONG_X = Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def fillet_loops(w, h, r, zc, fil, flip, dy=0.0, n=5):
    """loop del raccordo quarto di cerchio sullo spigolo esterno: zc = quota della faccia, flip=-1 verso -z."""
    out = []
    for i in range(n + 1):
        ph = math.pi / 2 * i / n
        ins = fil * (1 - math.cos(ph))
        out.append((rr_loop(w - 2 * ins, h - 2 * ins, r - ins, dy=dy), zc + flip * (fil - fil * math.sin(ph))))
    return out


def web_pts(x, y, r, hx, hy):
    """colonna vite raccordata alle due pareti dell'angolo (cerchio + raccordo pieno fino a (hx, hy))."""
    sx, sy = math.copysign(1, x), math.copysign(1, y)
    X, Y = sx * hx, sy * hy
    return [(x + px, y + py) for px, py in circle(r, 32)] + [(x - sx * r, Y), (X, Y), (X, y - sy * r)]


def dome(name, c, g=0.0, z_top=None):
    """solido dell'iPod (frontale piatto + fascia + cupola), ingrandito di g su lati e dorso."""
    zt = -PLATE if z_top is None else z_top
    loops = [(rr_loop(DEV_W + 2 * g, DEV_L + 2 * g, DEV_R + g), zt),
             (rr_loop(DEV_W + 2 * g, DEV_L + 2 * g, DEV_R + g), -PLATE - DEV_BAND)]
    k = (DEV_T - DEV_BAND) / DEV_DOME_X ** 2            # spessore = DEV_T - k*(DOME - inset)^2 (parabola)
    for i in range(1, 11):
        z = DEV_BAND + (DEV_T - DEV_BAND) * i / 10
        ix = DEV_DOME_X - math.sqrt((DEV_T - z) / k)
        iy = ix * DEV_DOME_Y / DEV_DOME_X
        loops.append((rr_loop(DEV_W + 2 * g - 2 * ix, DEV_L + 2 * g - 2 * iy, max(DEV_R - ix, 1.0) + g), -PLATE - z - g))
    return hull(name, loops, c)


# ---------------------------------------------------------------- pezzi
def btn_specs():
    """(along, s0, s1, u_dev, u_out): tasti volume (bordo sx, lungo y) e accensione (bordo alto, lungo x).
    s0..s1 = estensione del tasto lungo il bordo; u_dev = bordo dell'iPod (+0.1); u_out = faccia esterna."""
    e = RIB_CLR                                                 # stesso piano per tasca e blocco: niente pellicole
    return [("y", VOL_Y0, VOL_Y1, -(DEV_W / 2 + e), -OW / 2),
            ("x", POWER_X - POWER_L / 2, POWER_X + POWER_L / 2, DEV_L / 2 + e, Y_TOP)]


def _xyz(along, s_, u, z):
    return (s_, u, z) if along == "x" else (u, s_, z)


def pocket(c, along, s0, s1, u_in, u_out, depth, z_face=0.0, flip=1, r_end=None, seg=10, u_end=None, top=True):
    """tasca aperta su faccia e fianco, taglio fermo al piano u_in. Il fondo si raccorda alle testate con un arco di
    raggio r_end (default depth+1 = quarto di cerchio fino alla faccia); oltre l'arco la testata sale dritta.
    flip=1 scende da z_face verso -z (cornice)."""
    sgn = 1 if u_out > u_in else -1
    ua, ub = u_in, (u_out + sgn * 3.0 if u_end is None else u_end)
    r = depth + 1.0 if r_end is None else r_end
    pts = []
    def add(ds, dz):
        for s_ in (s0 - ds, s1 + ds):
            for u in (ua, ub):
                pts.append(Vector(_xyz(along, s_, u, z_face + flip * dz)))
    for k in range(seg + 1):
        th = math.pi / 2 * k / seg
        add(r * math.sin(th), -depth + r * (1 - math.cos(th)))
    if top:
        add(r, 1.0)
    return hull("t", [], c, pts3=pts)


def btn_pockets(c):
    out = []
    for along, s0, s1, ud, uo in btn_specs():
        out.append(pocket(c, along, s0 - POCKET_M, s1 + POCKET_M, ud, uo, POCKET_D, r_end=DOCK_R_END))   # stesso raccordo della spina
        # smusso 45° del frontale sopra il tasto (solo se BTN_RELIEF > 0)
        if BTN_RELIEF <= 0:
            continue
        sgn = 1 if uo > ud else -1
        a, b, rl = s0 - POCKET_M, s1 + POCKET_M, BTN_RELIEF
        pts = []
        for zz, ui, g in ((-PLATE, ud, 0.0), (1.0, ud - sgn * (rl + 1.0), rl + 1.0)):
            for s_ in (a - g, b + g):
                for u in (ui, uo + sgn * 3.0):
                    pts.append(Vector(_xyz(along, s_, u, zz)))
        out.append(hull("t", [], c, pts3=pts))
    return out


def dock_cut(c, z0, z1, y_in):
    """fessura dritta per la spina, sezione rettangolare DOCK_W x (z0..z1)."""
    return [box("t", -DOCK_W / 2, DOCK_W / 2, Y_BOT - 1, y_in, z0, z1, c)]


def pocket_blocks(c):
    """cornice: blocco pieno fra bordo dell'iPod e parete attorno a ogni conca (e ai lati della spina):
    chiude il corridoio vuoto, così nella conca si vedono solo l'iPod e plastica piena."""
    out = []
    z0, z1 = -F, -PLATE + 0.05                                  # fino al giunto: fianchi della fessura e delle tasche senza gradini
    for along, s0, s1, ud, uo in btn_specs():
        sgn = 1 if uo > ud else -1
        u0, u1 = ud, uo - sgn * 1.0
        e0, e1 = s0 - POCKET_M - POCKET_D - 1.0 - END_WALL, s1 + POCKET_M + POCKET_D + 1.0 + END_WALL
        if along == "y":
            out.append(box("t", min(u0, u1), max(u0, u1), e0, e1, z0, z1, c))
        else:
            out.append(box("t", e0, e1, min(u0, u1), max(u0, u1), z0, z1, c))
    yd = -(DEV_L / 2 + RIB_CLR)
    xg = DOCK_W / 2 - DOCK_Z0 + 1.0 + END_WALL                  # copre la tasca fino alle testate a 45°
    out.append(box("t", -xg, xg, -IL / 2 - 1, yd, z0, z1, c))
    return out


def towers(c):
    """scocca: sotto le conche, torrette sagomate sulla cupola che chiudono il cuneo vuoto sotto il bordo curvo
    dell'iPod fino alla fascia piatta. Si montano da dietro (nessun sottosquadro)."""
    out = []
    zt = -(PLATE + DEV_BAND + 1.5)                             # sotto la fascia: niente lama contro la cupola
    for along, s0, s1, ud, uo in btn_specs():
        sgn = 1 if uo > ud else -1
        u0, u1 = ud - sgn * (RIB_CLR + TOWER_SETBACK), ud - sgn * 9.5   # accorciate: lasciano libero il fianco curvo coi tasti
        e0, e1 = s0 - POCKET_M - 1.5, s1 + POCKET_M + 1.5          # quanto basta sotto la tasca, lontano dall'angolo dell'iPod
        lim = (DEV_W if along == "x" else DEV_L) / 2 - DEV_R + 0.5   # non entra nell'angolo raggiato dell'iPod (lama sottile)
        e0, e1 = max(e0, -lim), min(e1, lim)
        if along == "y":
            t = box("t", min(u0, u1), max(u0, u1), e0, e1, FLOOR - 0.1, zt, c)
        else:
            t = box("t", e0, e1, min(u0, u1), max(u0, u1), FLOOR - 0.1, zt, c)
        boolean(t, dome("t", c, CRADLE_CLR, z_top=1.0), "DIFFERENCE")
        out.append(t)
    return out


def soften_pockets(ob):
    """arrotonda gli spigoli vivi (diedro > SOFT_ANG) nella zona delle conche dei tasti."""
    zones = []
    for along, s0, s1, ud, uo in btn_specs():
        a, b = s0 - POCKET_M - DOCK_R_END - 1.0, s1 + POCKET_M + DOCK_R_END + 1.0
        u0, u1 = sorted((ud - (BTN_RELIEF + 0.5) * (1 if uo > ud else -1), uo + (2 if uo > ud else -2)))   # fuori dalle colonne viti
        zones.append((a, b, u0, u1) if along == "x" else (u0, u1, a, b))   # (x0, x1, y0, y1)
    planes = [(0 if along == "y" else 1, ud, 1 if uo > ud else -1) for along, s0, s1, ud, uo in btn_specs()]
    def under_plate(e):                                         # spigoli sotto il frontale o dal lato iPod (non si vedono): esclusi
        m = (e.verts[0].co + e.verts[1].co) / 2
        if any(math.hypot(m.x - x, m.y - y) < COL_R + 0.5 for x, y in SCREWS):   # attaccati alla colonna della vite
            return True
        return m.z < -PLATE + 0.3 and any((m[k] - u) * sg < 0.6 and abs(m[k] - u) < 6 for k, u, sg in planes)
    def inside(v):
        x, y, z = v.co
        return z > -F - 0.01 and any(x0 <= x <= x1 and y0 <= y <= y1 for x0, x1, y0, y1 in zones)
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts[:], edges=bm.edges[:])   # facce complanari unite
    bmesh.ops.dissolve_degenerate(bm, dist=1e-3, edges=bm.edges[:])
    lim = math.radians(SOFT_ANG)
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > lim
             and inside(e.verts[0]) and inside(e.verts[1])
             and min(e.verts[0].co.z, e.verts[1].co.z) > -(F - GROOVE_FLOOR) - 0.3 and not under_plate(e)]   # non verso il piano di giunzione
    bmesh.ops.bevel(bm, geom=edges, offset=SOFT_R, offset_type="OFFSET", segments=SOFT_SEG, profile=0.5,
                    affect="EDGES", clamp_overlap=False)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=bm.edges[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data); bm.free()
    return len(edges)


def build_cornice(c):
    body = hull("cornice", [(rr_loop(OW - 2 * CH, OL - 2 * CH, OUT_R - CH, dy=YB), 0.0),
                            (rr_loop(OW, OL, OUT_R, dy=YB), -CH), (rr_loop(OW, OL, OUT_R, dy=YB), -F)], c)
    boolean(body, prism("t", rr_loop(IWF, ILF, IRF), -F - 1, -PLATE, c), "DIFFERENCE")   # tasca iPod
    # labbro: continuazione della parete interna, entra nella cavità della scocca con LIP_CLR di gioco
    lip = prism("lip", rr_loop(IW - 2 * LIP_CLR, IL - 2 * LIP_CLR, IR - LIP_CLR), -F - LIP_H, -F + 0.02, c)
    lcuts = [prism("t", rr_loop(IWF, ILF, IRF), -F - LIP_H - 1, -F + 1, c)]
    for x, y in SCREWS:                                        # tacche per le colonne (raccordate) della scocca
        lcuts.append(prism("t", web_pts(x, y, COL_R + 0.3, IW / 2 + 1, IL / 2 + 1), -F - LIP_H - 1, -F - 0.01, c))
    boolean(lip, lcuts, "DIFFERENCE")
    adds = [lip]
    for x, y in SCREWS:                                        # colonne per gli inserti M2, raccordate alle pareti
        adds.append(prism("t", web_pts(x, y, COL_R, IWF / 2 + 0.5, ILF / 2 + 0.5), -F, -PLATE + 0.05, c))
    # nervature di centraggio (2 per lato lungo, 1 in alto, 2 in basso ai lati del tunnel)
    RW, RL, z0, z1 = DEV_W / 2 + RIB_CLR, DEV_L / 2 + RIB_CLR, -F + 0.6, -PLATE + 0.05
    for ry in (-45.0, 45.0):
        adds.append(box("t", -IWF / 2 - 1, -RW, ry - 5, ry + 5, z0, z1, c))
        adds.append(box("t", RW, IWF / 2 + 1, ry - 5, ry + 5, z0, z1, c))
    adds.append(box("t", -13.0, -11.0, RL, ILF / 2 + 1, z0, z1, c))
    adds += pocket_blocks(c)
    boolean(body, adds, "UNION")

    cuts = []
    for x, y in ALL_SCREWS:                                    # sedi inserti (angoli + mento)
        cuts.append(cyl("t", (x, y, -F - 1), (x, y, -F + INS_DEPTH), INS_HOLE / 2, c, 24))
    cuts.append(hull("t", [(rr_loop(WIN_W, WIN_L, WIN_R), -PLATE - 1), (rr_loop(WIN_W, WIN_L, WIN_R), -WIN_CH),
                           (rr_loop(WIN_W + 2 * WIN_CH + 2, WIN_L + 2 * WIN_CH + 2, WIN_R + WIN_CH + 1), 1.0)], c))   # smusso 45°
    hr = HOME_HOLE_D / 2
    cuts.append(hull("t", [(circle(hr, 48), -PLATE - 1), (circle(hr, 48), -HOME_CH), (circle(hr + HOME_CH + 1, 48), 1.0)], c,
                     Matrix.Translation((0, HOME_Y, 0))))
    cuts += btn_pockets(c)                                     # tasche dei tasti (45°, tetto piano)
    for along, s0, s1, ud, uo in btn_specs():                  # fondo delle conche spiovente verso l'iPod (testate comprese):
        sgn = 1 if uo > ud else -1                             # a filo esterno profondità POCKET_D (come v2), sul bordo dell'iPod
        d_in = F - GROOVE_FLOOR                                # F - GROOVE_FLOOR; raccordi concentrici (stesso centro, raggio + calo)
        k = (d_in - POCKET_D) / abs(uo - ud)                   # pendenza (mm di calo per mm verso l'iPod)
        a, b = s0 - POCKET_M, s1 + POCKET_M
        parts = []
        for u, du in ((ud - sgn * 0.5, -0.5), (uo, abs(uo - ud)), (uo + sgn * 3.0, abs(uo - ud) + 3.0)):
            dep = d_in - k * du                                # stesso piano anche fuori dal pezzo (taglio convesso)
            parts.append(pocket(c, along, a, b, u, u + sgn * 0.01, dep, r_end=DOCK_R_END + dep - POCKET_D,
                                u_end=u + sgn * 0.01, top=False))
        pts = []
        for ob in parts:
            pts += [ob.matrix_world @ v.co for v in ob.data.vertices]
            me = ob.data; bpy.data.objects.remove(ob); bpy.data.meshes.remove(me)
        cuts.append(hull("t", [], c, pts3=pts))
    # spina: tasca come quelle dei tasti, aperta su frontale e bordo basso, testate 45°, fondo appena sotto il connettore
    cuts.append(pocket(c, "x", -DOCK_W / 2, DOCK_W / 2, -(DEV_L / 2) + 0.3, Y_BOT, -DOCK_Z0, r_end=DOCK_R_END))   # fino sopra la porta
    boolean(body, cuts, "DIFFERENCE")
    soften_pockets(body)                                       # conche dei tasti morbide, senza spigoli vivi
    if TEXT:
        boolean(body, text_cutter(c), "DIFFERENCE")
    return body


def text_cutter(c):
    """TEXT in rilievo da sottrarre: si legge guardando il fianco destro (+x) col frontale in alto, centrata sulla
    fascia dritta del fianco (fra lo smusso del frontale e il piano di battuta)."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = TEXT
    cu.font = bpy.data.fonts.load(TEXT_FONT, check_existing=True)
    cu.align_x, cu.align_y = "CENTER", "BOTTOM"
    cu.extrude = 1.0
    tmp = bpy.data.objects.new("txt", cu); c.objects.link(tmp)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
    bpy.data.objects.remove(tmp); bpy.data.curves.remove(cu)
    cu2 = bpy.data.curves.new("cap", "FONT"); cu2.body = "S"; cu2.font = bpy.data.fonts.load(TEXT_FONT, check_existing=True)
    t2 = bpy.data.objects.new("cap", cu2); c.objects.link(t2)
    m2 = bpy.data.meshes.new_from_object(t2.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    cap = max(v.co.y for v in m2.vertices) - min(v.co.y for v in m2.vertices)
    bpy.data.objects.remove(t2); bpy.data.curves.remove(cu2); bpy.data.meshes.remove(m2)
    k = TEXT_CAP / cap
    ob = bpy.data.objects.new("t", me); c.objects.link(ob)
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    for v in bm.verts:                                         # testo: x lettura, y alto, z (+-1) normale
        lx, ly, lz = v.co.x * k, v.co.y * k, v.co.z
        v.co = Vector((OW / 2 + 1.0 if lz > 0 else OW / 2 - TEXT_DEPTH,          # da 1 mm fuori a TEXT_DEPTH dentro
                       YB + lx, -(CH + F) / 2 - TEXT_CAP / 2 + ly))
    zs = [v.co.z for v in bm.verts]                            # centrata (ascendenti e trattino basso compresi) sulla fascia dritta
    dz = -(CH + F) / 2 - (min(zs) + max(zs)) / 2
    for v in bm.verts:
        v.co.z += dz
    bm.to_mesh(me); bm.free()
    return ob


def build_scocca(c):
    body = hull("scocca", [(rr_loop(OW, OL, OUT_R, dy=YB), -F), (rr_loop(OW, OL, OUT_R, dy=YB), ZB + CH),
                           (rr_loop(OW - 2 * CH, OL - 2 * CH, OUT_R - CH, dy=YB), ZB)], c)
    # bocchettone cavo sonda sul bordo alto (blocco a filo del dorso: si stampa senza supporti)
    nose = hull("t", [(rect(CABLE_X - NOSE_W / 2, CABLE_X + NOSE_W / 2, Y_TOP - 3, Y_TOP + NOSE_L - 1.0), ZB),
                      (rect(CABLE_X - NOSE_W / 2, CABLE_X + NOSE_W / 2, Y_TOP - 3, Y_TOP + NOSE_L - 1.0), -F - 0.3),
                      (rect(CABLE_X - NOSE_W / 2 + 1, CABLE_X + NOSE_W / 2 - 1, Y_TOP - 3, Y_TOP + NOSE_L), ZB + 1),
                      (rect(CABLE_X - NOSE_W / 2 + 1, CABLE_X + NOSE_W / 2 - 1, Y_TOP - 3, Y_TOP + NOSE_L), -F - 1.3)], c)
    boolean(body, nose, "UNION")
    boolean(body, prism("t", rr_loop(IW, IL, IR), FLOOR, -F + 1, c), "DIFFERENCE")      # cavità (il mento resta pieno)
    adds = []
    for x, y in SCREWS:                                        # colonne passaggio viti, raccordate alle pareti
        adds.append(prism("t", web_pts(x, y, COL_R, IW / 2 + 0.5, IL / 2 + 0.5), FLOOR - 0.1, -F - 0.02, c))
    # costole trasversali sagomate sulla cupola: l'iPod ci appoggia il dorso e resta centrato
    xe = DEV_W / 2 - 0.5                                        # dentro la sagoma dell'iPod: non toccano blocchi e labbro della cornice
    for ry in CRADLE_Y:
        rib = box("t", -xe, xe, ry - CRADLE_T / 2, ry + CRADLE_T / 2, FLOOR - 0.1, -(PLATE + DEV_T + CRADLE_CLR), c)
        boolean(rib, dome("t", c, CRADLE_CLR, z_top=1.0), "DIFFERENCE")
        adds.append(rib)
        for cx in CRUSH_X:                                     # listelli di schiacciamento al centro della costola
            cr = box("t", cx - 1.5, cx + 1.5, ry - CRUSH_W / 2, ry + CRUSH_W / 2, FLOOR - 0.1, -(PLATE + DEV_T - CRUSH_INT) + 0.5, c)
            sh = dome("t", c, 0.0, z_top=1.0)
            sh.data.transform(Matrix.Translation((0, 0, CRUSH_INT)))     # iPod spostato verso il vetro: il listello entra di CRUSH_INT
            boolean(cr, sh, "DIFFERENCE")
            adds.append(cr)
    # soglia piena sotto lo scasso della spina, sagomata sulla curva del fondo dell'iPod: chiude la vista nel vano
    ys = -(IL / 2 - LIP_T - LIP_CLR - 0.3)
    sill = box("t", -(DOCK_W / 2 + 3.0), DOCK_W / 2 + 3.0, ys, -DEV_L / 2 + DEV_DOME_Y + 1.0, FLOOR - 0.1, -F - 0.02, c)
    boolean(sill, dome("t", c, CRADLE_CLR, z_top=1.0), "DIFFERENCE")
    adds.append(sill)
    zl = -F - LIP_H - 0.3                                      # sotto il labbro della cornice
    xf = DOCK_W / 2 + 3.0
    adds.append(box("t", -xf, xf, -IL / 2 - 0.5, ys + 0.3, FLOOR - 0.1, zl, c))   # riempimento dietro la tacca
    adds += towers(c)
    for bx in (CABLE_X - 5.0, CABLE_X + 5.0):                  # ponticelli fascetta: la fascetta passa sotto, il cavo in mezzo
        bar = box("t", bx - 1, bx + 1, TIE_Y - 3.5, TIE_Y + 3.5, FLOOR - 0.1, FLOOR + 3.2, c)
        boolean(bar, box("t", bx - 2, bx + 2, TIE_Y - 2.3, TIE_Y + 2.3, FLOOR - 1, FLOOR + 1.6, c), "DIFFERENCE")
        adds.append(bar)
    boolean(body, adds, "UNION")
    # foro del cavo a goccia (punta verso l'alto in stampa: niente sbalzi) con imbocco svasato a 45°
    r = CABLE_D / 2
    drop = [(r * math.cos(2 * math.pi * k / 32), r * math.sin(2 * math.pi * k / 32)) for k in range(32)] + [(0.0, r * math.sqrt(2))]
    M_cab = Matrix.Translation((CABLE_X, 0, ZC)) @ M_ALONG_Y            # sezione nel piano (x, z), estrusa lungo y
    cuts = [prism("t", drop, IL / 2 - 3, Y_TOP + NOSE_L + 1, c, M_cab)]
    big = [(x * (r + 1.0) / r, z * (r + 1.0) / r) for x, z in drop]
    cuts.append(hull("t", [(drop, Y_TOP + NOSE_L - 1.0), (big, Y_TOP + NOSE_L + 0.01), (big, Y_TOP + NOSE_L + 1)], c, M_cab))
    for x, y in ALL_SCREWS:
        cuts.append(cyl("t", (x, y, ZB - 1), (x, y, -F + 1), SCREW_HOLE / 2, c, 24))
        cuts.append(cyl("t", (x, y, ZB - 1), (x, y, ZB + CB_DEPTH), CB_D / 2, c, 32))
    # tacca sotto la spina nel bordo alto della scocca: il dito passa sotto il connettore (fondo piano, testate 45°)
    boolean(body, cuts, "DIFFERENCE")
    return body


def build_ipod(c):
    ip = dome("iPod_touch4_rif", c)
    scr = hull("display_rif", [(rr_loop(SCR_W, SCR_L, 0.5), -PLATE - 0.3), (rr_loop(SCR_W, SCR_L, 0.5), -PLATE + 0.02)], c)
    home = hull("home_rif", [(circle(HOME_D / 2), -PLATE - 0.5), (circle(HOME_D / 2), -PLATE + 0.02)], c,
                Matrix.Translation((0, HOME_Y, 0)))
    return ip, scr, home


# ---------------------------------------------------------------- main
def get_coll(name, clear=True):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    elif clear:
        for ob in list(c.objects):
            me = ob.data
            bpy.data.objects.remove(ob)
            if me and me.users == 0:
                bpy.data.meshes.remove(me)
    return c


def main(export=True, parts=None):
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"
    sc.unit_settings.scale_length = 0.001
    sc.unit_settings.length_unit = "MILLIMETERS"
    cube = bpy.data.objects.get("Cube")
    if cube and cube.type == "MESH" and len(cube.data.vertices) == 8:
        bpy.data.objects.remove(cube)
    c, r = get_coll(COLL), get_coll(REF)
    cornice, scocca = build_cornice(c), build_scocca(c)
    ipod, scr, home = build_ipod(r)
    mats = {cornice: material("SF_bianco", (0.85, 0.86, 0.88), 0.45),
            scocca: material("SF_grigio_scuro", (0.22, 0.24, 0.27), 0.5),
            ipod: material("SF_ipod", (0.02, 0.02, 0.025), 0.3),
            scr: material("SF_display", (0.03, 0.10, 0.12), 0.15),
            home: material("SF_home", (0.06, 0.06, 0.07), 0.4)}
    for ob, m in mats.items():
        ob.data.materials.clear()
        ob.data.materials.append(m)
    report = {}
    prints = {cornice: Matrix.Rotation(math.pi, 4, "X"),          # faccia in giù
              scocca: Matrix.Translation((0, 0, -ZB))}            # dorso sul piatto
    os.makedirs(OUT_DIR, exist_ok=True)
    for ob, M in prints.items():
        bad, vol = check(ob)
        bb = [M @ v.co for v in ob.data.vertices]
        size = [round(max(p[i] for p in bb) - min(p[i] for p in bb), 1) for i in range(3)]
        path = os.path.join(OUT_DIR, f"saturimetro_{ob.name}_{VERSION}.stl")
        if export and (parts is None or ob.name in parts):
            write_stl([ob], path, M)
        report[ob.name] = dict(non_manifold_edges=bad, volume_cm3=round(vol / 1000, 1), print_size_mm=size,
                               z_min=round(min(p.z for p in bb), 3), stl=path if export else None)
    report["guscio_mm"] = [round(OW, 1), round(OL, 1), round(-ZB, 1)]
    report["viti_xy"] = [(round(x, 2), round(y, 2)) for x, y in ALL_SCREWS]
    return report


if __name__ == "__main__":
    RESULT = main()
    print(RESULT)
