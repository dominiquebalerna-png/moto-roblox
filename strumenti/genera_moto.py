"""
Genera il modello 3D della moto (Yamaha YZ125, blu) come file GLB per Roblox.

Le misure sono prese dalla foto laterale (pixel) e convertite in stud:
1 stud = 0,28 m, passo (interasse) reale 1443 mm = 385 px nella foto.

Sistema di riferimento (come Roblox):
  origine = asse della ruota dietro, +Y = su, -Z = davanti, +X = lato destro della moto.
  Il terreno e' a Y = -1.19 (asse davanti a Y = +0.04: la gomma da 21" e' piu' grande).

Ogni pezzo si chiama  Gruppo_Colore_Nome. Lo script Roblox usa il Gruppo per
sapere cosa si muove insieme e il Colore per colore e materiale.

Uso:  python3 genera_moto.py  ->  scrive ../MotoYZ125.glb
"""

import math
import os
from collections import defaultdict

import numpy as np
import trimesh
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

S = 1443.0 / 385.0 / 280.0  # stud per pixel della foto
ASSE_DIETRO_PX = (100.0, 279.0)

# Colori usati solo per l'anteprima (in Roblox li decide lo script)
COLORI = {
    "Blu": (18, 42, 190),
    "BluCerchio": (22, 52, 175),
    "Nero": (22, 22, 24),
    "NeroOpaco": (35, 35, 38),
    "Gomma": (28, 28, 28),
    "Alluminio": (172, 174, 178),
    "Oro": (176, 138, 62),
    "Cromo": (205, 205, 210),
    "Molla": (205, 140, 55),
    "Argento": (190, 190, 195),
    "Motore": (150, 152, 158),
    "Sella": (24, 24, 26),
    "Ciano": (60, 185, 235),
    "Bianco": (235, 235, 235),
    "Disco": (150, 150, 156),
    "Rif": (255, 0, 255),
}

pezzi = defaultdict(list)  # (gruppo, colore) -> [mesh]


def P(px, py):
    """Pixel della foto -> (z, y) in stud."""
    return (-(px - ASSE_DIETRO_PX[0]) * S, (ASSE_DIETRO_PX[1] - py) * S)


def P3(px, py, x=0.0):
    z, y = P(px, py)
    return np.array([x, y, z])


def aggiungi(gruppo, colore, mesh):
    pezzi[(gruppo, colore)].append(mesh)


# ---------------------------------------------------------------- utilita'

def liscia_anello(punti, suddivisioni=4):
    """Curva chiusa Catmull-Rom che passa per i punti (per plastiche morbide)."""
    p = np.asarray(punti, float)
    n = len(p)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = p[(i - 1) % n], p[i], p[(i + 1) % n], p[(i + 2) % n]
        for k in range(suddivisioni):
            t = k / suddivisioni
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return np.array(out)


def rientra(anello, b):
    """Sposta ogni vertice verso l'interno di b (anello antiorario)."""
    n = len(anello)
    out = np.empty_like(anello)
    for i in range(n):
        a, c, d = anello[i - 1], anello[i], anello[(i + 1) % n]
        e1 = c - a
        e2 = d - c
        n1 = np.array([-e1[1], e1[0]]) / (np.linalg.norm(e1) + 1e-9)
        n2 = np.array([-e2[1], e2[0]]) / (np.linalg.norm(e2) + 1e-9)
        m = n1 + n2
        m /= np.linalg.norm(m) + 1e-9
        k = max(np.dot(m, n1), 0.5)
        out[i] = c + m * (b / k)
    return out


def costante(v):
    return lambda z, y: v


def piastra(poligono_px, xa, xb, ba=0.0, bb=0.0, liscio=True):
    """Solido con il profilo laterale dato (in pixel), tra x = xa(z,y) e x = xb(z,y).
    ba / bb = smusso sulla faccia a (lato -X) e sulla faccia b (lato +X)."""
    if not callable(xa):
        xa = costante(xa)
    if not callable(xb):
        xb = costante(xb)
    anello = np.array([P(*p) for p in poligono_px])
    if liscio:
        anello = liscia_anello(anello)
    poly = orient(Polygon(anello), 1.0)
    anello = np.array(poly.exterior.coords)[:-1]
    n = len(anello)
    dentro_a = rientra(anello, ba) if ba > 0 else anello
    dentro_b = rientra(anello, bb) if bb > 0 else anello

    def cap(ring):
        _, f = trimesh.creation.triangulate_polygon(Polygon(ring), engine="earcut")
        return np.asarray(f) % n

    def v3(ring, fx, extra=0.0):
        return np.array([[fx(z, y) + extra, y, z] for z, y in ring])

    vert, facce = [], []

    def blocco(v):
        base = sum(len(x) for x in vert)
        vert.append(v)
        return base

    # anelli: A0 = faccia a (rientrata), A1 = bordo a, B1 = bordo b, B0 = faccia b
    A0 = blocco(v3(dentro_a, xa))
    A1 = blocco(v3(anello, xa, ba))
    B1 = blocco(v3(anello, xb, -bb))
    B0 = blocco(v3(dentro_b, xb))
    capA = blocco(v3(dentro_a, xa))
    capB = blocco(v3(dentro_b, xb))

    def fascia(r0, r1):
        for i in range(n):
            j = (i + 1) % n
            facce.append([r0 + i, r0 + j, r1 + j])
            facce.append([r0 + i, r1 + j, r1 + i])

    # il profilo e' antiorario nel piano (z, y) visto da +X
    fascia(A0, A1)
    fascia(A1, B1)
    fascia(B1, B0)
    for f in cap(dentro_a):
        facce.append([capA + f[0], capA + f[2], capA + f[1]])
    for f in cap(dentro_b):
        facce.append([capB + f[0], capB + f[1], capB + f[2]])

    m = trimesh.Trimesh(np.vstack(vert), np.array(facce), process=False)
    # ordina le facce in modo che le normali escano dal solido
    if m.volume < 0:
        m.invert()
    return m


def specchia(m):
    m2 = m.copy()
    m2.vertices[:, 0] *= -1
    m2.invert()
    return m2


def tubo(percorso, raggi, lati=12, chiuso=False, tappi=True, smussa=True):
    """Tubo lungo un percorso 3D (punti in stud), con raggio per punto."""
    p = np.asarray(percorso, float)
    if smussa and len(p) > 2 and not chiuso:
        # arrotonda il percorso: suddivide con Catmull-Rom aperta
        q = [p[0]]
        r_in = np.broadcast_to(np.asarray(raggi, float), (len(p),))
        rr = [r_in[0]]
        for i in range(len(p) - 1):
            p0 = p[max(i - 1, 0)]
            p1, p2 = p[i], p[i + 1]
            p3 = p[min(i + 2, len(p) - 1)]
            for k in range(1, 5):
                t = k / 4
                q.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                                + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
                rr.append(r_in[i] + (r_in[i + 1] - r_in[i]) * t)
        p = np.array(q)
        raggi = np.array(rr)
    n = len(p)
    r = np.broadcast_to(np.asarray(raggi, float), (n,))
    tang = np.zeros_like(p)
    for i in range(n):
        if chiuso:
            d = p[(i + 1) % n] - p[i - 1]
        else:
            d = p[min(i + 1, n - 1)] - p[max(i - 1, 0)]
        tang[i] = d / (np.linalg.norm(d) + 1e-12)
    ref = np.array([0, 0, 1.0]) if abs(tang[0][2]) < 0.9 else np.array([1.0, 0, 0])
    nrm = np.cross(tang[0], ref)
    nrm /= np.linalg.norm(nrm)
    norms = []
    for i in range(n):
        if i > 0:
            nrm = nrm - tang[i] * np.dot(nrm, tang[i])
            nrm /= np.linalg.norm(nrm) + 1e-12
        norms.append(nrm.copy())
    vert = []
    for i in range(n):
        b = np.cross(tang[i], norms[i])
        for k in range(lati):
            a = 2 * math.pi * k / lati
            vert.append(p[i] + r[i] * (math.cos(a) * norms[i] + math.sin(a) * b))
    facce = []
    seg = n if chiuso else n - 1
    for i in range(seg):
        i2 = (i + 1) % n
        for k in range(lati):
            k2 = (k + 1) % lati
            facce.append([i * lati + k, i2 * lati + k, i2 * lati + k2])
            facce.append([i * lati + k, i2 * lati + k2, i * lati + k2])
    vert = list(vert)
    if tappi and not chiuso:
        c0 = len(vert)
        vert.append(p[0])
        c1 = len(vert)
        vert.append(p[-1])
        for k in range(lati):
            k2 = (k + 1) % lati
            facce.append([c0, k2, k])
            facce.append([c1, (n - 1) * lati + k, (n - 1) * lati + k2])
    m = trimesh.Trimesh(np.array(vert), np.array(facce), process=False)
    if m.is_volume and m.volume < 0:
        m.invert()
    return m


def cilindro(a, b, r, lati=16):
    return tubo([a, b], [r, r], lati=lati, smussa=False)


def scatola(centro, dimensioni, rot=None):
    m = trimesh.creation.box(extents=dimensioni)
    if rot is not None:
        T = np.eye(4)
        T[:3, :3] = rot
        m.apply_transform(T)
    m.apply_translation(centro)
    return m


def rivoluzione(profilo, centro, segmenti=48):
    """Ruota un profilo [(raggio, x), ...] attorno all'asse X passante per centro."""
    prof = np.asarray(profilo, float)
    m = len(prof)
    vert = []
    for s in range(segmenti):
        a = 2 * math.pi * s / segmenti
        for r, x in prof:
            vert.append([centro[0] + x, centro[1] + r * math.cos(a), centro[2] + r * math.sin(a)])
    facce = []
    for s in range(segmenti):
        s2 = (s + 1) % segmenti
        for k in range(m):
            k2 = (k + 1) % m
            facce.append([s * m + k, s2 * m + k, s2 * m + k2])
            facce.append([s * m + k, s2 * m + k2, s * m + k2])
    mesh = trimesh.Trimesh(np.array(vert), np.array(facce), process=False)
    if mesh.volume < 0:
        mesh.invert()
    return mesh


def rot_x(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def ruota_attorno(m, asse_punto, a):
    T = np.eye(4)
    T[:3, :3] = rot_x(a)
    m.apply_translation(-np.asarray(asse_punto))
    m.apply_transform(T)
    m.apply_translation(asse_punto)
    return m


# ------------------------------------------------------------------ ruote

def ruota(gruppo, centro, r_cerchio, r_gomma, mezza_largh_gomma, mezza_largh_cerchio,
          r_mozzo, mezza_mozzo, x_disco, r_disco, corona=None):
    cx, cy, cz = centro
    # --- gomma (sezione ovale) ---
    r_base = r_gomma - 0.055
    a_rad = (r_base - r_cerchio) / 2 + 0.01
    rc = r_cerchio + a_rad - 0.01
    prof = []
    for k in range(18):
        t = 2 * math.pi * k / 18
        prof.append((rc + a_rad * math.cos(t), mezza_largh_gomma * math.sin(t)))
    aggiungi(gruppo, "Gomma", rivoluzione(prof, centro, 56))
    # --- tasselli ---
    file = 44
    for i in range(file):
        a = 2 * math.pi * i / file
        if i % 2 == 0:
            posizioni = [(0.0, 0.0), (mezza_largh_gomma * 0.78, 0.55), (-mezza_largh_gomma * 0.78, 0.55)]
        else:
            posizioni = [(mezza_largh_gomma * 0.38, 0.2), (-mezza_largh_gomma * 0.38, 0.2)]
        for x_off, incl in posizioni:
            t = math.asin(max(-0.95, min(0.95, x_off / mezza_largh_gomma)))
            r_sup = rc + a_rad * math.cos(t)
            h = 0.065
            k = scatola([x_off, r_sup + h / 2 - 0.01, 0], [0.075, h, 0.075],
                        rot=np.array([[math.cos(incl * np.sign(x_off)), -math.sin(incl * np.sign(x_off)), 0],
                                      [math.sin(incl * np.sign(x_off)), math.cos(incl * np.sign(x_off)), 0],
                                      [0, 0, 1]]))
            T = np.eye(4)
            T[:3, :3] = rot_x(a)
            k.apply_transform(T)
            k.apply_translation(centro)
            aggiungi(gruppo, "Gomma", k)
    # --- cerchio (canale a U) ---
    w = mezza_largh_cerchio
    prof_c = [(r_cerchio - 0.075, -w * 0.8), (r_cerchio - 0.02, -w), (r_cerchio + 0.015, -w),
              (r_cerchio + 0.015, -w * 0.85), (r_cerchio - 0.01, -w * 0.7), (r_cerchio - 0.01, w * 0.7),
              (r_cerchio + 0.015, w * 0.85), (r_cerchio + 0.015, w), (r_cerchio - 0.02, w),
              (r_cerchio - 0.075, w * 0.8)]
    aggiungi(gruppo, "BluCerchio", rivoluzione(prof_c, centro, 56))
    # --- mozzo ---
    aggiungi(gruppo, "Alluminio", cilindro([cx - mezza_mozzo, cy, cz], [cx + mezza_mozzo, cy, cz], r_mozzo * 0.65))
    for s in (-1, 1):
        aggiungi(gruppo, "BluCerchio", cilindro([cx + s * (mezza_mozzo * 0.55 - 0.02), cy, cz],
                                                [cx + s * (mezza_mozzo * 0.55 + 0.02), cy, cz], r_mozzo))
    # --- raggi (36, incrociati) ---
    for i in range(36):
        a = 2 * math.pi * i / 36
        lato = 1 if i % 2 == 0 else -1
        incrocio = 0.33 * (1 if (i // 2) % 2 == 0 else -1)
        p0 = np.array([cx + lato * mezza_mozzo * 0.55, cy + r_mozzo * 0.9 * math.cos(a), cz + r_mozzo * 0.9 * math.sin(a)])
        a2 = a + incrocio
        rr = r_cerchio - 0.07
        p1 = np.array([cx + lato * 0.025, cy + rr * math.cos(a2), cz + rr * math.sin(a2)])
        aggiungi(gruppo, "Cromo", tubo([p0, p1], [0.012, 0.012], lati=5, smussa=False))
    # --- disco freno a margherita ---
    prof_d = []
    for k in range(72):
        t = 2 * math.pi * k / 72
        rr = r_disco * (1 + 0.035 * math.cos(12 * t))
        prof_d.append((math.cos(t) * rr, math.sin(t) * rr))
    disco_out = Polygon(prof_d)
    disco = disco_out.difference(Polygon([(math.cos(2 * math.pi * k / 40) * r_disco * 0.62,
                                           math.sin(2 * math.pi * k / 40) * r_disco * 0.62) for k in range(40)]))
    md = trimesh.creation.extrude_polygon(disco, 0.03)
    # extrude_polygon: profilo nel piano XY, spessore lungo Z -> portalo nel piano YZ
    md.apply_transform(np.array([[0, 0, 1, 0], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]], float))
    md.apply_translation([cx + x_disco - 0.015, cy, cz])
    aggiungi(gruppo, "Disco", md)
    # portadisco
    for k in range(5):
        a = 2 * math.pi * k / 5
        p0 = [cx + x_disco, cy + r_mozzo * 0.7 * math.cos(a), cz + r_mozzo * 0.7 * math.sin(a)]
        p1 = [cx + x_disco, cy + r_disco * 0.68 * math.cos(a), cz + r_disco * 0.68 * math.sin(a)]
        aggiungi(gruppo, "Disco", tubo([p0, p1], [0.025, 0.025], lati=6, smussa=False))
    # --- corona (ruota dietro, lato sinistro) ---
    if corona:
        x_cor, r_cor = corona
        dent = []
        for k in range(96):
            t = 2 * math.pi * k / 96
            rr = r_cor * (1.0 if (k // 2) % 2 == 0 else 0.94)
            dent.append((math.cos(t) * rr, math.sin(t) * rr))
        cor = Polygon(dent).difference(Polygon([(math.cos(2 * math.pi * k / 24) * r_mozzo * 0.8,
                                                 math.sin(2 * math.pi * k / 24) * r_mozzo * 0.8) for k in range(24)]))
        mc = trimesh.creation.extrude_polygon(cor, 0.03)
        mc.apply_transform(np.array([[0, 0, 1, 0], [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 0, 1]], float))
        mc.apply_translation([cx + x_cor - 0.015, cy, cz])
        aggiungi(gruppo, "Motore", mc)


ASSE_DAVANTI = P3(485, 276)  # la gomma davanti (21") e' piu' alta: asse 3 px piu' su
R_GOMMA_DIETRO = 89 * S
R_GOMMA_DAVANTI = 92 * S

ruota("RuotaDietro", P3(*ASSE_DIETRO_PX), r_cerchio=241 / 280, r_gomma=R_GOMMA_DIETRO,
      mezza_largh_gomma=0.19, mezza_largh_cerchio=0.10, r_mozzo=0.2, mezza_mozzo=0.3,
      x_disco=0.24, r_disco=0.435, corona=(-0.25, 0.40))
ruota("RuotaDavanti", ASSE_DAVANTI, r_cerchio=267 / 280, r_gomma=R_GOMMA_DAVANTI,
      mezza_largh_gomma=0.15, mezza_largh_cerchio=0.075, r_mozzo=0.17, mezza_mozzo=0.24,
      x_disco=-0.2, r_disco=0.48)

# ---------------------------------------------------------------- forcella

PEND = 0.445  # inclinazione della forcella nella foto (dx/dy in pixel)


def su_forcella(py, spost_px=0.0):
    """Punto (px, py) sulla linea dei foderi, spostato in avanti di spost_px."""
    px = 477.0 - PEND * (279.0 - py)
    nrm = np.array([1.0, -PEND]) / math.hypot(1, PEND)
    return px + nrm[0] * spost_px, py + nrm[1] * spost_px


X_STELI = 0.36
for s in (-1, 1):
    x = s * X_STELI
    a = P3(*su_forcella(42), x)
    b = P3(*su_forcella(200), x)
    aggiungi("Sterzo", "Oro", cilindro(a, b, 0.105, 20))
    # anelli neri in cima e in fondo al fodero oro
    aggiungi("Sterzo", "Nero", cilindro(P3(*su_forcella(40), x), P3(*su_forcella(46), x), 0.11, 20))
    aggiungi("Sterzo", "Nero", cilindro(P3(*su_forcella(194), x), P3(*su_forcella(203), x), 0.112, 20))
    # stelo cromato + parasteli neri + piedino
    aggiungi("Forcella", "Cromo", cilindro(P3(*su_forcella(195), x), P3(*su_forcella(268), x), 0.085, 16))
    guard = [su_forcella(198, 3), su_forcella(198, 11), su_forcella(262, 12), su_forcella(270, 4)]
    aggiungi("Forcella", "Nero", piastra(guard, x + s * 0.04 - 0.05, x + s * 0.04 + 0.05, 0.015, 0.015, liscio=False))
    aggiungi("Forcella", "Nero", piastra([su_forcella(255, -6), su_forcella(255, 7), (494, 284), (482, 292), (470, 286)],
                                         x - 0.1, x + 0.1, 0.03, 0.03, liscio=False))

# piastre di sterzo (sopra e sotto)
for py, h in ((58, 0.13), (127, 0.16)):
    centro = P3(*su_forcella(py, -3))
    dirf = np.array([0, 1.0, PEND]) / math.hypot(1, PEND)  # lungo la forcella, verso l'alto
    terzo = np.cross([1.0, 0, 0], dirf)
    R = np.column_stack([[1.0, 0, 0], dirf, terzo])
    aggiungi("Sterzo", "Alluminio", scatola(centro, [2 * X_STELI + 0.26, h, 0.34], rot=R))
    aggiungi("Sterzo", "Nero", cilindro(centro + [0, 0, 0.12], centro + [0, 0, 0.12] + dirf * 0.05, 0.08, 12))

# manubrio
cima = P3(*su_forcella(52, -6))
morsetti = cima + np.array([0, 0.2, 0.02])
for s in (-1, 1):
    aggiungi("Sterzo", "Alluminio", scatola(morsetti + [s * 0.2, -0.05, 0], [0.12, 0.16, 0.16]))
manub = []
for xs, dy, dz in ((-1.42, 0.10, 0.30), (-1.05, 0.10, 0.28), (-0.6, 0.05, 0.12), (-0.25, 0.0, 0.0),
                   (0.25, 0.0, 0.0), (0.6, 0.05, 0.12), (1.05, 0.10, 0.28), (1.42, 0.10, 0.30)):
    manub.append(morsetti + np.array([xs, dy, dz]))
aggiungi("Sterzo", "NeroOpaco", tubo(manub, 0.045, lati=10))
aggiungi("Sterzo", "BluCerchio", scatola(morsetti + [0, 0.06, -0.02], [0.5, 0.1, 0.12]))  # paracolpi
for s in (-1, 1):
    g0 = morsetti + np.array([s * 1.08, 0.10, 0.285])
    g1 = morsetti + np.array([s * 1.46, 0.10, 0.30])
    aggiungi("Sterzo", "Nero", cilindro(g0, g1, 0.07, 14))  # manopole
    # pompa freno / frizione + leva
    pompa = morsetti + np.array([s * 0.88, 0.1, 0.25])
    aggiungi("Sterzo", "Nero", scatola(pompa + [0, 0.03, 0], [0.16, 0.12, 0.14]))
    leva = [pompa + [s * 0.05, 0.02, -0.08], pompa + [s * 0.35, 0.0, -0.18], pompa + [s * 0.6, -0.02, -0.12]]
    aggiungi("Sterzo", "Alluminio", tubo(leva, 0.022, lati=6))
# tubo freno davanti (lungo la forcella sinistra)
tubof = [morsetti + [-0.88, 0.08, 0.2], P3(*su_forcella(60, 14), -0.25), P3(*su_forcella(150, 14), -0.45),
         P3(*su_forcella(240, 12), -0.45)]
aggiungi("Sterzo", "Nero", tubo(tubof, 0.018, lati=6))

# tabella portanumero davanti
tabella = [(379, 44), (392, 45), (403, 62), (414, 86), (421, 106), (421, 117), (409, 120), (398, 98), (388, 74)]
aggiungi("Sterzo", "Blu", piastra(tabella, -0.38, 0.38, 0.05, 0.05))

# parafango davanti
paraf = [(407, 117), (428, 112), (458, 110), (492, 112), (520, 119), (541, 131), (555, 148),
         (540, 142), (516, 130), (488, 124), (456, 123), (428, 126), (410, 129)]


def largh_paraf(z, y):
    zt = P(555, 0)[0]
    z0 = P(407, 0)[0]
    t = (z - z0) / (zt - z0)
    return 0.34 - 0.12 * max(0.0, min(1.0, t))


aggiungi("Sterzo", "Blu", piastra(paraf, lambda z, y: -largh_paraf(z, y), largh_paraf, 0.04, 0.04))
# pinza freno davanti (lato sinistro, sul piedino)
aggiungi("Forcella", "Nero", scatola(ASSE_DAVANTI + [-0.3, 0.25, 0.28], [0.12, 0.3, 0.28]))

# ---------------------------------------------------------------- telaio

for s in (-1, 1):
    x = s * 0.3
    trave = [P3(400, 100, s * 0.12), P3(350, 140, x), P3(295, 170, x), P3(262, 195, x), P3(252, 232, x), P3(256, 262, x)]
    aggiungi("Corpo", "Alluminio", tubo(trave, 0.1, lati=8))
    sotto = [P3(256, 262, x), P3(285, 282, s * 0.22), P3(335, 280, s * 0.15), P3(368, 230, 0.0)]
    aggiungi("Corpo", "Alluminio", tubo(sotto, 0.06, lati=8))
    tel_post = [P3(258, 172, x * 0.9), P3(200, 140, x * 0.85), P3(130, 124, x * 0.8)]
    aggiungi("Corpo", "Alluminio", tubo(tel_post, 0.05, lati=8))
    tel_post2 = [P3(250, 212, x * 0.9), P3(205, 175, x * 0.85), P3(150, 132, x * 0.8)]
    aggiungi("Corpo", "Alluminio", tubo(tel_post2, 0.04, lati=8))
    # piastra del perno forcellone
    aggiungi("Corpo", "Alluminio", piastra([(240, 205), (265, 200), (270, 262), (248, 268), (238, 240)],
                                           x - 0.06, x + 0.06, 0.02, 0.02))
# cannotto di sterzo + discesa
cann_a = P3(*su_forcella(60, -9))
cann_b = P3(*su_forcella(132, -9))
aggiungi("Corpo", "Alluminio", cilindro(cann_a, cann_b, 0.12, 16))
aggiungi("Corpo", "Alluminio", tubo([P3(*su_forcella(128, -9)), P3(385, 175), P3(368, 230)], 0.09, lati=8))

# perno forcellone
PERNO_FORCELLONE = P3(252, 247)
aggiungi("Corpo", "Cromo", cilindro(PERNO_FORCELLONE + [-0.45, 0, 0], PERNO_FORCELLONE + [0.45, 0, 0], 0.05, 10))

# ---------------------------------------------------------------- motore

aggiungi("Corpo", "Motore", piastra([(246, 218), (270, 204), (300, 207), (330, 217), (343, 240), (336, 262),
                                     (312, 277), (270, 277), (250, 264), (240, 240)], -0.27, 0.27, 0.07, 0.07))
aggiungi("Corpo", "Alluminio", rivoluzione([(0.0, 0.27), (0.29, 0.27), (0.3, 0.3), (0.27, 0.34), (0.0, 0.345)],
                                           P3(287, 243), 32))  # carter frizione (destra)
aggiungi("Corpo", "Motore", rivoluzione([(0.0, -0.27), (0.22, -0.27), (0.23, -0.3), (0.2, -0.33), (0.0, -0.335)],
                                        P3(275, 248), 32))  # carter accensione (sinistra)
# cilindro con alette
cil = [(280, 186), (318, 182), (330, 216), (302, 222), (286, 216)]
aggiungi("Corpo", "NeroOpaco", piastra(cil, -0.2, 0.2, 0.04, 0.04, liscio=False))
for k in range(5):
    py = 186 + k * 7
    alette = [(279 + k * 0.5, py), (319 + k * 2.2, py - 0.5), (320 + k * 2.2, py + 2.5), (280 + k * 0.5, py + 3)]
    aggiungi("Corpo", "Motore", piastra(alette, -0.24, 0.24, 0.0, 0.0, liscio=False))
aggiungi("Corpo", "NeroOpaco", piastra([(283, 176), (314, 173), (318, 183), (282, 186)], -0.17, 0.17, 0.03, 0.03, liscio=False))
# carburatore + cassa filtro (nascosti in parte)
aggiungi("Corpo", "NeroOpaco", cilindro(P3(275, 200), P3(250, 190), 0.11, 12))

# espansione (marmitta a espansione nera) e silenziatore
espansione = [P3(318, 204, 0.05), P3(338, 200, 0.12), P3(352, 210, 0.2), P3(361, 232, 0.24),
              P3(362, 255, 0.24), P3(355, 270, 0.2), P3(335, 278, 0.1), P3(300, 270, 0.05),
              P3(262, 230, 0.2), P3(232, 205, 0.26), P3(185, 196, 0.26)]
raggi_esp = [0.1, 0.13, 0.17, 0.2, 0.2, 0.18, 0.15, 0.12, 0.1, 0.09, 0.09]
aggiungi("Corpo", "NeroOpaco", tubo(espansione, raggi_esp, lati=14))
sil = [P3(172, 190, 0.26), P3(96, 143, 0.26)]
aggiungi("Corpo", "Argento", tubo(sil, [0.155, 0.155], lati=18, smussa=False))
aggiungi("Corpo", "Nero", cilindro(P3(98, 144, 0.26), P3(83, 135, 0.26), 0.15, 18))
aggiungi("Corpo", "Nero", cilindro(P3(176, 193, 0.26), P3(168, 188, 0.26), 0.16, 18))

# ammortizzatore dietro
amm_su, amm_giu = P3(248, 150), P3(240, 205)
aggiungi("Corpo", "Oro", cilindro(amm_su, amm_giu, 0.075, 14))
aggiungi("Corpo", "Nero", cilindro(amm_su + [0, 0.06, 0], amm_su - [0, 0.05, 0], 0.11, 14))
asse = (amm_giu - amm_su) / np.linalg.norm(amm_giu - amm_su)
spire = []
L = np.linalg.norm(amm_giu - amm_su) * 0.8
u = np.cross(asse, [1, 0, 0])
u /= np.linalg.norm(u)
v = np.cross(asse, u)
for k in range(7 * 12 + 1):
    t = k / 12 * 2 * math.pi
    spire.append(amm_su + asse * (0.08 + L * k / (7 * 12)) + 0.15 * (math.cos(t) * u + math.sin(t) * v))
aggiungi("Corpo", "Molla", tubo(spire, 0.03, lati=6, smussa=False))
aggiungi("Corpo", "NeroOpaco", cilindro(P3(232, 150, 0.15), P3(222, 185, 0.15), 0.07, 12))  # serbatoio gas

# pedane, pedale freno, leva cambio
for s in (-1, 1):
    ped = P3(262, 258, s * 0.6)
    aggiungi("Corpo", "Alluminio", scatola(ped, [0.5, 0.06, 0.2]))
    for k in range(4):
        aggiungi("Corpo", "Alluminio", scatola(ped + [s * (-0.18 + k * 0.12), 0.04, 0], [0.03, 0.04, 0.22]))
aggiungi("Corpo", "Alluminio", tubo([P3(258, 252, 0.42), P3(285, 262, 0.45), P3(300, 266, 0.5)], 0.03, lati=6))
aggiungi("Corpo", "Alluminio", tubo([P3(262, 240, -0.4), P3(285, 248, -0.45), P3(296, 247, -0.55)], 0.025, lati=6))
aggiungi("Corpo", "Alluminio", tubo([P3(300, 230, 0.36), P3(285, 215, 0.42), P3(265, 210, 0.45)], 0.022, lati=6))  # kick

# ---------------------------------------------------------------- plastiche

sella = [(100, 119), (150, 117), (200, 119), (250, 121), (272, 119), (290, 112), (299, 111),
         (298, 118), (284, 130), (262, 145), (240, 150), (205, 152), (186, 158), (160, 138), (135, 123), (100, 124)]


def largh_sella(z, y):
    zf = P(299, 0)[0]
    zr = P(100, 0)[0]
    t = (z - zr) / (zf - zr)
    return 0.44 - 0.12 * max(0.0, min(1.0, t))


aggiungi("Corpo", "Sella", piastra(sella, lambda z, y: -largh_sella(z, y), largh_sella, 0.1, 0.1))

paraf_d = [(14, 120), (50, 116), (100, 115), (140, 119), (230, 126), (230, 132), (140, 127), (100, 125), (50, 123), (14, 122)]


def largh_paraf_d(z, y):
    zt = P(14, 0)[0]
    z0 = P(200, 0)[0]
    t = (z - z0) / (zt - z0)
    return 0.42 - 0.17 * max(0.0, min(1.0, t))


aggiungi("Corpo", "Blu", piastra(paraf_d, lambda z, y: -largh_paraf_d(z, y), largh_paraf_d, 0.03, 0.03))

fianchetto = [(86, 124), (136, 121), (160, 138), (186, 158), (191, 167), (178, 173), (158, 170), (130, 160),
              (100, 147), (88, 136)]
f_dx = piastra(fianchetto, 0.36, 0.43, 0.0, 0.025)
aggiungi("Corpo", "Blu", f_dx)
aggiungi("Corpo", "Blu", specchia(f_dx))
filtro = [(178, 178), (214, 149), (238, 140), (252, 147), (250, 198), (206, 201), (182, 194)]
fl = piastra(filtro, 0.25, 0.38, 0.0, 0.02, liscio=False)
aggiungi("Corpo", "Nero", fl)
aggiungi("Corpo", "Nero", specchia(fl))
# viti dei fianchetti
for px, py in ((145, 127), (200, 133), (163, 165)):
    for s in (-1, 1):
        aggiungi("Corpo", "Alluminio", cilindro(P3(px, py, s * 0.43), P3(px, py, s * 0.45), 0.025, 8))

# serbatoio + convogliatori radiatore
conv = [(258, 122), (280, 113), (300, 107), (320, 101), (338, 96), (360, 96), (380, 103), (405, 110),
        (424, 113), (420, 126), (410, 142), (400, 160), (390, 178), (380, 192), (372, 203), (355, 200),
        (335, 196), (312, 193), (295, 190), (278, 180), (262, 165), (255, 145)]


def largh_conv(z, y):
    px = 100 - z / S
    py = 279 - y / S
    if px < 280:
        w = 0.36
    elif px < 355:
        w = 0.36 + 0.18 * (px - 280) / 75
    else:
        w = 0.54
    # davanti in alto si stringe (dietro ai foderi della forcella)
    if px > 392 and py < 150:
        w -= (px - 392) / 28 * 0.3
    return max(w, 0.2)


aggiungi("Corpo", "Blu", piastra(conv, lambda z, y: -largh_conv(z, y), largh_conv, 0.09, 0.09))

# radiatore (griglia scura visibile nel convogliatore)
rad = [(330, 146), (385, 140), (395, 155), (345, 161)]
for s in (-1, 1):
    m = piastra(rad, lambda z, y: largh_conv(z, y) - 0.06, lambda z, y: largh_conv(z, y) + 0.004, 0, 0)
    aggiungi("Corpo", "NeroOpaco", m if s > 0 else specchia(m))

# grafiche sui convogliatori
grafiche = {
    "Nero": [(300, 128), (400, 120), (398, 131), (355, 137), (305, 138)],
    "Ciano": [(290, 121), (395, 114), (396, 117), (290, 124)],
    "Bianco": [(330, 127), (372, 124), (371, 128), (331, 131)],
}
# seconda riga azzurra in basso + scritta bianca sul convogliatore
for colore, poly in (("Ciano", [(300, 165), (392, 170), (392, 173), (300, 168)]),
                     ("Bianco", [(348, 179), (372, 178), (372, 189), (348, 190)])):
    grafiche.setdefault(colore + "_2", poly)
for colore, poly in grafiche.items():
    colore = colore.split("_")[0]
    m = piastra(poly, lambda z, y: largh_conv(z, y) - 0.02, lambda z, y: largh_conv(z, y) + 0.008, 0, 0, liscio=False)
    aggiungi("Corpo", colore, m)
    aggiungi("Corpo", colore, specchia(m))
# piccolo logo bianco sul fianchetto
for s in (-1, 1):
    m = piastra([(245, 168), (262, 167), (262, 176), (245, 177)], 0.43, 0.437, 0, 0, liscio=False)
    m2 = piastra([(350, 166), (368, 166), (368, 172), (350, 172)], lambda z, y: largh_conv(z, y) - 0.01,
                 lambda z, y: largh_conv(z, y) + 0.008, 0, 0, liscio=False)
    aggiungi("Corpo", "Bianco", m2 if s > 0 else specchia(m2))

# ---------------------------------------------------------------- forcellone

fc = [(92, 266), (150, 255), (205, 244), (242, 235), (258, 233), (262, 258), (240, 263), (200, 267),
      (150, 278), (106, 292), (92, 290)]
for s in (-1, 1):
    m = piastra(fc, 0.33, 0.47, 0.03, 0.03)
    aggiungi("Forcellone", "Alluminio", m if s > 0 else specchia(m))
    # tendicatena
    aggiungi("Forcellone", "Alluminio", scatola(P3(92, 279, s * 0.4), [0.16, 0.16, 0.25]))
aggiungi("Forcellone", "Alluminio", scatola(P3(245, 248), [0.75, 0.3, 0.22]))
aggiungi("Forcellone", "Alluminio", cilindro(P3(*ASSE_DIETRO_PX, -0.48), P3(*ASSE_DIETRO_PX, 0.48), 0.05, 10))
# pinza freno dietro (destra) + pattino catena
aggiungi("Forcellone", "Nero", scatola(P3(112, 303, 0.3), [0.12, 0.3, 0.32]))
aggiungi("Forcellone", "NeroOpaco", piastra([(150, 254), (240, 236), (240, 244), (150, 262)], -0.47, -0.4, 0, 0.01, liscio=False))

# catena (lato sinistro)
pign = P3(270, 250, -0.25)
cor = P3(*ASSE_DIETRO_PX, -0.25)
r_cor, r_pign = 0.40, 0.11
cat = []
for k in range(24):  # mezzo giro attorno alla corona: sopra -> dietro -> sotto
    a = math.pi * k / 23
    cat.append(cor + [0, r_cor * math.cos(a), r_cor * math.sin(a)])
for k in range(12):  # mezzo giro attorno al pignone: sotto -> davanti -> sopra
    a = math.pi + math.pi * k / 11
    cat.append(pign + [0, r_pign * math.cos(a), r_pign * math.sin(a)])
aggiungi("Forcellone", "NeroOpaco", tubo(cat, 0.035, lati=6, chiuso=True, smussa=False))

# ---------------------------------------------------------------- riferimenti

for nome, pos in (("Origine", [0, 0, 0]), ("Avanti", [0, 0, -5.0]), ("Su", [0, 3.0, 0])):
    pezzi[("Rif", nome)].append(scatola(pos, [0.05, 0.05, 0.05]))


# ---------------------------------------------------------------- esporta

def costruisci_scena():
    scena = trimesh.Scene()
    totale = 0
    for (gruppo, colore), mesh_list in sorted(pezzi.items()):
        m = trimesh.util.concatenate(mesh_list)
        m.remove_unreferenced_vertices()
        nome = f"{gruppo}_{colore}" if gruppo != "Rif" else f"RIF_{colore}"
        rgb = COLORI.get(colore, COLORI["Rif"])
        m.visual = trimesh.visual.TextureVisuals(material=trimesh.visual.material.PBRMaterial(
            name=nome, baseColorFactor=[*(c / 255 for c in rgb), 1.0],
            metallicFactor=0.6 if colore in ("Alluminio", "Cromo", "Oro", "Argento", "Disco", "Motore") else 0.0,
            roughnessFactor=0.35))
        totale += len(m.faces)
        print(f"{nome:28s} {len(m.faces):6d} triangoli")
        assert len(m.faces) < 20000, nome
        scena.add_geometry(m, node_name=nome, geom_name=nome)
    print("totale triangoli:", totale)
    return scena


if __name__ == "__main__":
    qui = os.path.dirname(os.path.abspath(__file__))
    uscita = os.path.join(qui, "..", "MotoYZ125.glb")
    costruisci_scena().export(uscita, file_type="glb", include_normals=True)
    print("scritto", os.path.abspath(uscita))
