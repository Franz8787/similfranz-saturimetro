// similFranzSat — generatore di QR code (vedi SFQRCode.h). Segue la norma ISO/IEC 18004.
#include "SFQRCode.h"
#include <string.h>
#include <stdlib.h>

static const int kEccPerBlock[11] = { 0, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26 };   // livello M
static const int kBlocks[11]      = { 0,  1,  1,  1,  2,  2,  4,  4,  4,  5,  5 };

typedef struct { int size; uint8_t *m; uint8_t fn[SFQR_MAX_SIZE * SFQR_MAX_SIZE]; } Grid;

static int RawModules(int ver) {
    int r = (16 * ver + 128) * ver + 64;
    if (ver >= 2) { int n = ver / 7 + 2; r -= (25 * n - 10) * n - 55; if (ver >= 7) r -= 36; }
    return r;
}
static int DataCodewords(int ver) { return RawModules(ver) / 8 - kEccPerBlock[ver] * kBlocks[ver]; }

static void SetFn(Grid *g, int x, int y, bool dark) { g->m[y * g->size + x] = dark; g->fn[y * g->size + x] = 1; }

static uint8_t GfMul(uint8_t x, uint8_t y) {
    int z = 0;
    for (int i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >> 7) * 0x11D); z ^= ((y >> i) & 1) * x; }
    return (uint8_t)z;
}
static void RsDivisor(int deg, uint8_t *out) {
    memset(out, 0, (size_t)deg); out[deg - 1] = 1; uint8_t root = 1;
    for (int i = 0; i < deg; i++) {
        for (int j = 0; j < deg; j++) { out[j] = GfMul(out[j], root); if (j + 1 < deg) out[j] ^= out[j + 1]; }
        root = GfMul(root, 0x02);
    }
}
static void RsRemainder(const uint8_t *data, int len, const uint8_t *div, int deg, uint8_t *out) {
    memset(out, 0, (size_t)deg);
    for (int i = 0; i < len; i++) {
        uint8_t f = data[i] ^ out[0];
        memmove(out, out + 1, (size_t)(deg - 1)); out[deg - 1] = 0;
        for (int j = 0; j < deg; j++) out[j] ^= GfMul(div[j], f);
    }
}

static void DrawFinder(Grid *g, int cx, int cy) {
    for (int dy = -4; dy <= 4; dy++) for (int dx = -4; dx <= 4; dx++) {
        int x = cx + dx, y = cy + dy, d = abs(dx) > abs(dy) ? abs(dx) : abs(dy);
        if (x >= 0 && x < g->size && y >= 0 && y < g->size) SetFn(g, x, y, d != 2 && d != 4);
    }
}
static void DrawFormat(Grid *g, int mask) {
    int data = (0 << 3) | mask, rem = data;              // livello M = 00
    for (int i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
    int bits = ((data << 10) | rem) ^ 0x5412, s = g->size;
#define BIT(i) (((bits >> (i)) & 1) != 0)
    for (int i = 0; i <= 5; i++) SetFn(g, 8, i, BIT(i));
    SetFn(g, 8, 7, BIT(6)); SetFn(g, 8, 8, BIT(7)); SetFn(g, 7, 8, BIT(8));
    for (int i = 9; i < 15; i++) SetFn(g, 14 - i, 8, BIT(i));
    for (int i = 0; i < 8; i++) SetFn(g, s - 1 - i, 8, BIT(i));
    for (int i = 8; i < 15; i++) SetFn(g, 8, s - 15 + i, BIT(i));
    SetFn(g, 8, s - 8, true);
#undef BIT
}
static void DrawFunctions(Grid *g, int ver) {
    int s = g->size;
    for (int i = 0; i < s; i++) { SetFn(g, 6, i, i % 2 == 0); SetFn(g, i, 6, i % 2 == 0); }
    DrawFinder(g, 3, 3); DrawFinder(g, s - 4, 3); DrawFinder(g, 3, s - 4);
    if (ver >= 2) {
        int n = ver / 7 + 2, step = (ver * 8 + n * 3 + 5) / (n * 4 - 4) * 2, pos[7];
        pos[0] = 6;
        for (int i = n - 1, p = s - 7; i >= 1; i--, p -= step) pos[i] = p;
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) {
            if ((i == 0 && j == 0) || (i == 0 && j == n - 1) || (i == n - 1 && j == 0)) continue;
            for (int dy = -2; dy <= 2; dy++) for (int dx = -2; dx <= 2; dx++)
                SetFn(g, pos[i] + dx, pos[j] + dy, (abs(dx) > abs(dy) ? abs(dx) : abs(dy)) != 1);
        }
    }
    DrawFormat(g, 0);
    if (ver >= 7) {
        int rem = ver;
        for (int i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >> 11) * 0x1F25);
        long bits = ((long)ver << 12) | rem;
        for (int i = 0; i < 18; i++) {
            bool b = ((bits >> i) & 1) != 0; int a = s - 11 + i % 3, c = i / 3;
            SetFn(g, a, c, b); SetFn(g, c, a, b);
        }
    }
}
static bool MaskBit(int mask, int x, int y) {
    switch (mask) {
        case 0: return (x + y) % 2 == 0;
        case 1: return y % 2 == 0;
        case 2: return x % 3 == 0;
        case 3: return (x + y) % 3 == 0;
        case 4: return (x / 3 + y / 2) % 2 == 0;
        case 5: return x * y % 2 + x * y % 3 == 0;
        case 6: return (x * y % 2 + x * y % 3) % 2 == 0;
        default: return ((x + y) % 2 + x * y % 3) % 2 == 0;
    }
}
static void ApplyMask(Grid *g, int mask) {
    for (int y = 0; y < g->size; y++) for (int x = 0; x < g->size; x++)
        if (!g->fn[y * g->size + x] && MaskBit(mask, x, y)) g->m[y * g->size + x] ^= 1;
}
// penalità semplificata (regole 1, 2 e 4 della norma): basta a evitare le maschere peggiori
static long Penalty(Grid *g) {
    int s = g->size; long p = 0, dark = 0;
    for (int pass = 0; pass < 2; pass++)
        for (int a = 0; a < s; a++) {
            int run = 1;
            for (int b = 1; b < s; b++) {
                uint8_t prev = pass ? g->m[(b - 1) * s + a] : g->m[a * s + b - 1], cur = pass ? g->m[b * s + a] : g->m[a * s + b];
                if (cur == prev) { run++; if (run == 5) p += 3; else if (run > 5) p++; } else run = 1;
            }
        }
    for (int y = 0; y < s - 1; y++) for (int x = 0; x < s - 1; x++) {
        uint8_t c = g->m[y * s + x];
        if (c == g->m[y * s + x + 1] && c == g->m[(y + 1) * s + x] && c == g->m[(y + 1) * s + x + 1]) p += 3;
    }
    for (int i = 0; i < s * s; i++) dark += g->m[i];
    long total = (long)s * s, k = (labs(dark * 20 - total * 10) + total - 1) / total - 1;
    if (k > 0) p += k * 10;
    return p;
}

bool SFQREncode(const uint8_t *text, int len, uint8_t modules[SFQR_MAX_SIZE * SFQR_MAX_SIZE], int *outSize) {
    int ver = 1;
    for (; ver <= 10; ver++) if (4 + (ver < 10 ? 8 : 16) + len * 8 <= DataCodewords(ver) * 8) break;
    if (ver > 10 || len < 0) return false;
    int cap = DataCodewords(ver);
    uint8_t data[400]; memset(data, 0, sizeof data); int bit = 0;
#define PUT(v, n) do { for (int _i = (n) - 1; _i >= 0; _i--) { if (((v) >> _i) & 1) data[bit >> 3] |= (uint8_t)(0x80 >> (bit & 7)); bit++; } } while (0)
    PUT(4, 4); PUT(len, ver < 10 ? 8 : 16);
    for (int i = 0; i < len; i++) PUT(text[i], 8);
    int term = cap * 8 - bit; PUT(0, term < 4 ? term : 4);
    bit = (bit + 7) & ~7;
    for (uint8_t pad = 0xEC; bit < cap * 8; pad ^= 0xEC ^ 0x11) PUT(pad, 8);
#undef PUT
    // blocchi con correzione d'errore, poi intreccio
    int nb = kBlocks[ver], ecl = kEccPerBlock[ver], raw = RawModules(ver) / 8;
    int nShort = nb - raw % nb, shortLen = raw / nb;
    uint8_t blocks[5][160], div[30], all[400]; int k = 0, n = 0;
    RsDivisor(ecl, div);
    for (int i = 0; i < nb; i++) {
        int dl = shortLen - ecl + (i < nShort ? 0 : 1);
        memcpy(blocks[i], data + k, (size_t)dl); k += dl;
        if (i < nShort) blocks[i][dl] = 0;
        RsRemainder(data + k - dl, dl, div, ecl, blocks[i] + shortLen + 1 - ecl);
    }
    for (int i = 0; i <= shortLen; i++) for (int j = 0; j < nb; j++)
        if (i != shortLen - ecl || j >= nShort) all[n++] = blocks[j][i];

    Grid g; g.size = ver * 4 + 17; g.m = modules;
    memset(modules, 0, SFQR_MAX_SIZE * SFQR_MAX_SIZE); memset(g.fn, 0, sizeof g.fn);
    DrawFunctions(&g, ver);
    int s = g.size, i = 0;
    for (int right = s - 1; right >= 1; right -= 2) {
        if (right == 6) right = 5;
        for (int v = 0; v < s; v++) for (int j = 0; j < 2; j++) {
            int x = right - j, y = ((right + 1) & 2) == 0 ? s - 1 - v : v;
            if (!g.fn[y * s + x] && i < n * 8) { g.m[y * s + x] = (all[i >> 3] >> (7 - (i & 7))) & 1; i++; }
        }
    }
    int best = 0; long bestP = -1;
    for (int mask = 0; mask < 8; mask++) {
        ApplyMask(&g, mask); DrawFormat(&g, mask);
        long p = Penalty(&g);
        if (bestP < 0 || p < bestP) { bestP = p; best = mask; }
        ApplyMask(&g, mask);
    }
    ApplyMask(&g, best); DrawFormat(&g, best);
    *outSize = s;
    return true;
}
