#include "SFQRCode.h"
#import "OxiScreenView.h"
#import "TraceView.h"

static UIColor *RGB(int r, int g, int b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }
#define GREEN  RGB(72, 235, 90)
#define CYAN   RGB(80, 220, 255)
#define WHITE  [UIColor whiteColor]
#define GRAY   RGB(150, 155, 160)
#define YELLOW RGB(255, 214, 0)
#define RED    RGB(255, 48, 40)

static void T(NSString *s, CGRect r, UIFont *f, UIColor *c, NSTextAlignment a) {
    [c set];
    [s drawInRect:r withFont:f lineBreakMode:NSLineBreakByClipping alignment:a];
}

// barra verticale accanto al pletismo: segue l'onda in tempo reale (vista piccola: ridisegno economico a 30 fps)
@interface OxiAmpBar : UIView
@property (nonatomic) double level;
@end
@implementation OxiAmpBar
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.opaque = YES; self.backgroundColor = [UIColor blackColor]; self.contentMode = UIViewContentModeRedraw; } return self; }
- (void)setLevel:(double)l { l = MAX(0, MIN(1, l)); if (fabs(l - _level) > 0.01) { _level = l; [self setNeedsDisplay]; } }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext(); CGRect b = self.bounds;
    [[UIColor blackColor] setFill]; CGContextFillRect(c, b);
    CGRect bar = CGRectInset(b, 0.5, 0.5);
    [GRAY setStroke]; CGContextSetLineWidth(c, 1); CGContextStrokeRect(c, bar);
    // segmenti impilati, come la barra a tacche del dispositivo
    int n = 10; CGFloat segH = (bar.size.height - 2) / n;
    int lit = (int)lround(_level * n);
    [CYAN setFill];
    for (int i = 0; i < lit; i++) CGContextFillRect(c, CGRectMake(bar.origin.x + 1.5, CGRectGetMaxY(bar) - 1 - (i + 1) * segH + 1, bar.size.width - 3, segH - 1.5));
}
@end

@implementation OxiScreenView {
    OxiAmpBar *_bar;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = YES; self.backgroundColor = [UIColor blackColor]; self.contentMode = UIViewContentModeRedraw;
        _bootProgress = -1; _spo2Text = @"---"; _prText = @"---"; _battery = 1;
        _spo2Low = 85; _spo2High = 100; _prLow = 30; _prHigh = 170;
        CGRect b = self.bounds;
        _trace = [[TraceView alloc] initWithFrame:[self plethRect:b]];
        _trace.traceColor = CYAN; _trace.sweepSpeed = 55; _trace.autoScale = YES; _trace.minSpan = 0.3;
        _trace.hidden = YES;
        [self addSubview:_trace];
        _bar = [[OxiAmpBar alloc] initWithFrame:[self barRect:b]]; _bar.hidden = YES;
        [self addSubview:_bar];
    }
    return self;
}
- (CGRect)plethRect:(CGRect)b { return CGRectMake(8, 128, b.size.width - 46, 44); }
- (CGRect)barRect:(CGRect)b { CGRect pr = [self plethRect:b]; return CGRectMake(CGRectGetMaxX(pr) + 10, pr.origin.y + 2, 11, pr.size.height - 4); }
- (void)layoutSubviews { [super layoutSubviews]; _trace.frame = [self plethRect:self.bounds]; _bar.frame = [self barRect:self.bounds]; }
- (void)setPulseAmp:(double)a { _pulseAmp = a; _bar.level = a; }
- (void)refresh { [self setNeedsDisplay]; }
- (NSString *)zoneAtPoint:(CGPoint)p {
    CGRect b = self.bounds, pr = [self plethRect:b];
    if (CGRectContainsPoint(CGRectInset(pr, -6, -6), p) || CGRectContainsPoint([self barRect:b], p)) return @"pleth";
    if (p.y >= 26 && p.y < pr.origin.y) return @"spo2";
    if (p.y >= CGRectGetMaxY(pr)) return @"pr";
    return nil;
}

- (void)setPowered:(BOOL)p { _powered = p; [self updateTrace]; [self setNeedsDisplay]; }
- (void)setMenu:(OxiMenu *)m { _menu = m; [self updateTrace]; }
- (void)setBootProgress:(double)v { _bootProgress = v; [self updateTrace]; [self setNeedsDisplay]; }
- (void)updateTrace { _trace.hidden = !(_powered && _bootProgress < 0 && (!_menu || _menu.page == OxiMenuClosed)); _bar.hidden = _trace.hidden; }

#pragma mark - Disegno

- (void)drawBattery:(CGContextRef)c at:(CGPoint)p {
    CGRect body = CGRectMake(p.x, p.y, 18, 9);
    [GRAY setStroke]; CGContextSetLineWidth(c, 1); CGContextStrokeRect(c, body);
    CGContextFillRect(c, CGRectMake(p.x + 18, p.y + 2.5, 2, 4));
    CGFloat w = 16 * MAX(0.04, MIN(1, _battery));
    [(_battery < 0.2 ? RED : (_charging ? CYAN : GREEN)) setFill];
    CGContextFillRect(c, CGRectMake(p.x + 1, p.y + 1, w, 7));
}
- (void)drawLink:(CGContextRef)c at:(CGPoint)p {
    // tre archi (Wi-Fi) verdi se collegato al monitor, grigi barrati altrimenti
    [(_linked ? GREEN : GRAY) setStroke]; CGContextSetLineWidth(c, 1.4);
    for (int i = 1; i <= 3; i++) { CGContextAddArc(c, p.x, p.y, 3.0 * i, -M_PI * 0.75, -M_PI * 0.25, 0); CGContextStrokePath(c); }
    [(_linked ? GREEN : GRAY) setFill]; CGContextFillEllipseInRect(c, CGRectMake(p.x - 1.3, p.y - 1.3, 2.6, 2.6));
    if (!_linked) { [RED setStroke]; CGContextSetLineWidth(c, 1.6); CGContextMoveToPoint(c, p.x - 8, p.y - 9); CGContextAddLineToPoint(c, p.x + 8, p.y + 2); CGContextStrokePath(c); }
}
- (void)drawSensorIcon:(CGContextRef)c at:(CGPoint)p {
    // omino del sensore: testa + busto (sensore applicato = pieno, altrimenti vuoto)
    UIColor *col = _sensorOn ? WHITE : GRAY;
    [col setStroke]; [col setFill]; CGContextSetLineWidth(c, 1.2);
    CGRect head = CGRectMake(p.x + 3, p.y, 6, 6);
    if (_sensorOn) CGContextFillEllipseInRect(c, head); else CGContextStrokeEllipseInRect(c, head);
    CGContextMoveToPoint(c, p.x, p.y + 13); CGContextAddCurveToPoint(c, p.x, p.y + 8, p.x + 12, p.y + 8, p.x + 12, p.y + 13);
    CGContextClosePath(c); if (_sensorOn) CGContextFillPath(c); else CGContextStrokePath(c);
}
- (void)drawBell:(CGContextRef)c at:(CGPoint)p crossed:(BOOL)x {
    [YELLOW setStroke]; [YELLOW setFill]; CGContextSetLineWidth(c, 1.3);
    CGContextMoveToPoint(c, p.x - 5, p.y + 4); CGContextAddLineToPoint(c, p.x - 3.5, p.y + 1.5); CGContextAddLineToPoint(c, p.x - 3.5, p.y - 1.5);
    CGContextAddArc(c, p.x, p.y - 1.5, 3.5, M_PI, 0, 0); CGContextAddLineToPoint(c, p.x + 3.5, p.y + 1.5); CGContextAddLineToPoint(c, p.x + 5, p.y + 4); CGContextClosePath(c); CGContextStrokePath(c);
    CGContextFillEllipseInRect(c, CGRectMake(p.x - 1.5, p.y + 4.5, 3, 3));
    if (x) { CGContextSetLineWidth(c, 1.8); CGContextMoveToPoint(c, p.x - 6, p.y - 6); CGContextAddLineToPoint(c, p.x + 6, p.y + 7); CGContextStrokePath(c); }
}

- (void)drawValue:(NSString *)txt rect:(CGRect)r flash:(OxiAlarmLevel)flash color:(UIColor *)col maxSize:(CGFloat)maxPt {
    UIFont *f = [UIFont boldSystemFontOfSize:MIN(maxPt, r.size.height * 0.98)];
    UIColor *fg = col;
    if (flash != OxiAlarmNone && _flashOn) {
        CGRect box = CGRectInset(r, 2, 6);
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:4];
        [(flash == OxiAlarmHigh ? RED : YELLOW) setFill]; [p fill];
        fg = flash == OxiAlarmHigh ? WHITE : [UIColor blackColor];
    }
    CGFloat th = f.lineHeight;
    T(txt, CGRectMake(r.origin.x, r.origin.y + (r.size.height - th) / 2, r.size.width, th), f, fg, NSTextAlignmentCenter);
}
- (void)drawLimits:(CGContextRef)c high:(NSInteger)hi low:(NSInteger)lo hiHit:(BOOL)hh loHit:(BOOL)lh rect:(CGRect)r {
    // staffa "]" con limite alto sopra e basso sotto, come sui saturimetri palmari
    [GRAY setStroke]; CGContextSetLineWidth(c, 1);
    CGFloat x = r.origin.x + 2, y0 = r.origin.y + 6, y1 = CGRectGetMaxY(r) - 6;
    CGContextMoveToPoint(c, x + 4, y0); CGContextAddLineToPoint(c, x, y0); CGContextAddLineToPoint(c, x, y1); CGContextAddLineToPoint(c, x + 4, y1); CGContextStrokePath(c);
    UIFont *f = [UIFont boldSystemFontOfSize:13];
    BOOL blinkHi = hh && _flashOn, blinkLo = lh && _flashOn;
    T([NSString stringWithFormat:@"%ld", (long)hi], CGRectMake(x + 7, y0 - 2, r.size.width - 9, 16), f, blinkHi ? RED : (hh ? YELLOW : WHITE), NSTextAlignmentLeft);
    T([NSString stringWithFormat:@"%ld", (long)lo], CGRectMake(x + 7, y1 - 14, r.size.width - 9, 16), f, blinkLo ? RED : (lh ? YELLOW : WHITE), NSTextAlignmentLeft);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    [[UIColor blackColor] setFill]; CGContextFillRect(c, rect);
    if (!_powered) {                                         // spento: schermo nero, ma il menu (Informazioni, indirizzo web app) resta consultabile
        if (_menu && _menu.page != OxiMenuClosed) [self drawMenu:c bounds:b];
        return;
    }
    if (_bootProgress >= 0) { [self drawBoot:c bounds:b]; return; }
    if (_menu && _menu.page != OxiMenuClosed) { [self drawMenu:c bounds:b]; return; }

    CGFloat W = b.size.width;
    // --- barra di stato ---
    if (_showLink) [self drawLink:c at:CGPointMake(14, 15)];
    if (_mutedRemaining > 0) {
        [self drawBell:c at:CGPointMake(34, 9) crossed:YES];
        T([NSString stringWithFormat:@"%ld:%02ld", (long)(_mutedRemaining / 60), (long)(_mutedRemaining % 60)], CGRectMake(43, 4, 40, 14), [UIFont boldSystemFontOfSize:11], YELLOW, NSTextAlignmentLeft);
    }
    if (_message.length) {
        UIColor *mc = _messageLevel == OxiAlarmHigh ? RED : _messageLevel == OxiAlarmMedium ? YELLOW : CYAN;
        BOOL blink = NO;                                     // il messaggio resta fisso: lampeggiano valore e limite violato
        CGFloat mx = _mutedRemaining > 0 ? 84 : 30, mw = W - 62 - mx;
        UIFont *mf = [UIFont boldSystemFontOfSize:11];
        if ([_message sizeWithFont:mf].width > mw) mf = [UIFont boldSystemFontOfSize:9];      // messaggio lungo: carattere più piccolo, mai tagliato
        if (!blink) T(_message, CGRectMake(mx, 4, mw, 14), mf, mc, NSTextAlignmentLeft);
    }
    // (batteria del dispositivo tolta dalla barra di stato: quella vera dell'iPod sta nell'intestazione dell'app)
    T(_dateText ?: @"", CGRectMake(W - 56, 1, 54, 11), [UIFont systemFontOfSize:9], GRAY, NSTextAlignmentRight);
    T(_timeText ?: @"", CGRectMake(W - 56, 11, 54, 11), [UIFont systemFontOfSize:9], GRAY, NSTextAlignmentRight);
    [GRAY setStroke]; CGContextSetLineWidth(c, 0.5); CGContextMoveToPoint(c, 6, 23.5); CGContextAddLineToPoint(c, W - 6, 23.5); CGContextStrokePath(c);

    // --- SpO2 ---
    CGFloat ySp = 26, hSp = 100;
    T(@"SpO2", CGRectMake(8, ySp + 2, 60, 18), [UIFont boldSystemFontOfSize:15], WHITE, NSTextAlignmentLeft);
    T(@"%", CGRectMake(50, ySp + 4, 20, 14), [UIFont systemFontOfSize:12], WHITE, NSTextAlignmentLeft);
    [self drawSensorIcon:c at:CGPointMake(10, ySp + 26)];
    T(_searching ? @"ricerca" : @"", CGRectMake(4, ySp + 44, 60, 12), [UIFont systemFontOfSize:9], GRAY, NSTextAlignmentLeft);
    [self drawValue:_spo2Text rect:CGRectMake(56, ySp + 14, W - 112, hSp - 14) flash:_spo2Flash color:CYAN maxSize:74];     // SpO2 azzurra, polso verde
    [self drawLimits:c high:_spo2High low:_spo2Low hiHit:_spo2HighHit loHit:_spo2LowHit rect:CGRectMake(W - 54, ySp + 18, 50, hSp - 22)];

    // --- pleth: la barra accanto al tracciato è una vista a parte (OxiAmpBar) che pulsa con l'onda ---
    CGRect pr = [self plethRect:b];

    // --- polso ---
    CGFloat yPr = CGRectGetMaxY(pr) + 4, hPr = b.size.height - yPr - 4;
    T(@"Polso", CGRectMake(8, yPr + 2, 60, 18), [UIFont boldSystemFontOfSize:15], WHITE, NSTextAlignmentLeft);
    T(@"BPM", CGRectMake(8, yPr + 22, 40, 14), [UIFont systemFontOfSize:11], WHITE, NSTextAlignmentLeft);
    [self drawValue:_prText rect:CGRectMake(56, yPr + 10, W - 112, hPr - 12) flash:_prFlash color:GREEN maxSize:50];   // polso più piccolo della SpO2
    [self drawLimits:c high:_prHigh low:_prLow hiHit:_prHighHit loHit:_prLowHit rect:CGRectMake(W - 54, yPr + 14, 50, hPr - 18)];
}

- (void)drawBoot:(CGContextRef)c bounds:(CGRect)b {
    CGFloat W = b.size.width, H = b.size.height;
    T(@"similFranz", CGRectMake(0, H * 0.28, W, 34), [UIFont boldSystemFontOfSize:30], WHITE, NSTextAlignmentCenter);
    T(@"Saturimetro", CGRectMake(0, H * 0.28 + 34, W, 22), [UIFont systemFontOfSize:18], CYAN, NSTextAlignmentCenter);
    T(@"SIMULAZIONE · NON PER USO CLINICO", CGRectMake(0, H * 0.28 + 60, W, 14), [UIFont systemFontOfSize:10], GRAY, NSTextAlignmentCenter);
    T(@"Autotest in corso…", CGRectMake(0, H * 0.70, W, 14), [UIFont systemFontOfSize:11], WHITE, NSTextAlignmentCenter);
    CGRect bar = CGRectMake(W * 0.2, H * 0.70 + 20, W * 0.6, 8);
    [GRAY setStroke]; CGContextSetLineWidth(c, 1); CGContextStrokeRect(c, bar);
    [GREEN setFill]; CGContextFillRect(c, CGRectMake(bar.origin.x + 1, bar.origin.y + 1, (bar.size.width - 2) * MAX(0, MIN(1, _bootProgress)), 6));
    T(_versionText ?: @"", CGRectMake(0, H - 16, W, 12), [UIFont systemFontOfSize:9], GRAY, NSTextAlignmentCenter);
}

- (void)drawMenu:(CGContextRef)c bounds:(CGRect)b {
    CGFloat W = b.size.width; OxiMenu *m = _menu;
    NSString *title = @"MENU";
    switch (m.page) {
        case OxiMenuLimits: title = @"LIMITI ALLARME"; break;
        case OxiMenuPulseVol: title = @"VOLUME POLSO"; break;
        case OxiMenuAlarmVol: title = @"VOLUME ALLARMI"; break;
        case OxiMenuInfo: title = @"INFORMAZIONI"; break;
        case OxiMenuConfirmReset: title = @"AZZERA SCENARIO"; break;
        case OxiMenuConnect: title = @"COLLEGAMENTO"; break;
        case OxiMenuPair: title = @"ABBINAMENTO DIRETTO"; break;
        case OxiMenuEco: title = @"ECOSISTEMA MONITOR"; break;
        default: break;
    }
    [RGB(30, 60, 100) setFill]; CGContextFillRect(c, CGRectMake(0, 0, W, 24));
    T(title, CGRectMake(8, 4, W - 16, 16), [UIFont boldSystemFontOfSize:14], WHITE, NSTextAlignmentLeft);
    UIFont *f = [UIFont systemFontOfSize:16], *fb = [UIFont boldSystemFontOfSize:16];
    __block CGFloat y = 36; CGFloat rowH = 30;
    void (^row)(NSString *, NSString *, BOOL, BOOL) = ^(NSString *label, NSString *value, BOOL sel, BOOL edit) {
        if (sel) { [(edit ? RGB(0, 90, 130) : RGB(40, 40, 40)) setFill]; CGContextFillRect(c, CGRectMake(6, y - 3, W - 12, rowH - 4)); }
        T(sel ? @"▸" : @"", CGRectMake(10, y, 14, 20), fb, CYAN, NSTextAlignmentLeft);
        T(label, CGRectMake(26, y, value ? W - 120 : W - 34, 20), sel ? fb : f, WHITE, NSTextAlignmentLeft);
        if (value) T(value, CGRectMake(W - 100, y, 90, 20), edit ? fb : f, edit ? YELLOW : GREEN, NSTextAlignmentRight);
        y += rowH;
    };
    switch (m.page) {
        case OxiMenuMain: {
            NSArray *items = [OxiMenu mainItems];
            for (NSUInteger i = 0; i < items.count; i++) row(items[i], nil, (NSInteger)i == m.cursor, NO);
            break;
        }
        case OxiMenuConnect: {
            NSArray *items = [OxiMenu connectItems];
            for (NSUInteger i = 0; i < items.count; i++) row(items[i], nil, (NSInteger)i == m.cursor, NO);
            T(@"Telefono da solo (hotspot) o rete con il monitor", CGRectMake(10, y + 8, W - 20, 30), [UIFont systemFontOfSize:11], GRAY, NSTextAlignmentLeft);
            break;
        }
        case OxiMenuLimits: {
            NSArray *keys = [OxiMenu limitKeys];
            for (NSUInteger i = 0; i < keys.count; i++) {
                BOOL sel = (NSInteger)i == m.cursor;
                NSString *v = [NSString stringWithFormat:@"%@%@", m.limits[keys[i]], [keys[i] hasPrefix:@"spo2"] ? @" %" : @" bpm"];
                row([OxiMenu limitTitle:keys[i]], v, sel, sel && m.editing);
            }
            row(@"Indietro", nil, m.cursor == (NSInteger)keys.count, NO);
            T(m.editing ? @"▲▼ modifica · ✓ conferma · ↩ annulla" : @"▲▼ scegli · ✓ modifica · ↩ menu", CGRectMake(8, b.size.height - 18, W - 16, 14), [UIFont systemFontOfSize:10], GRAY, NSTextAlignmentLeft);
            break;
        }
        case OxiMenuPulseVol: case OxiMenuAlarmVol: {
            NSInteger v = m.page == OxiMenuPulseVol ? m.pulseVolume : m.alarmVolume;
            T(m.page == OxiMenuPulseVol ? @"Tono del polso" : @"Allarmi", CGRectMake(12, 40, W - 24, 20), fb, WHITE, NSTextAlignmentLeft);
            for (int i = 0; i < 10; i++) {
                CGRect r = CGRectMake(14 + i * ((W - 28) / 10.0), 100 - i * 4, (W - 28) / 10.0 - 4, 24 + i * 4);
                [(i < v ? GREEN : RGB(50, 55, 60)) setFill]; CGContextFillRect(c, r);
            }
            T([NSString stringWithFormat:@"%ld / 10", (long)v], CGRectMake(12, 140, W - 24, 24), [UIFont boldSystemFontOfSize:22], GREEN, NSTextAlignmentCenter);
            T(@"▲▼ regola · ✓ o ↩ torna al menu", CGRectMake(8, b.size.height - 18, W - 16, 14), [UIFont systemFontOfSize:10], GRAY, NSTextAlignmentLeft);
            break;
        }
        case OxiMenuInfo: {
            CGFloat yy = 32;
            for (NSString *line in m.infoLines) { T(line, CGRectMake(10, yy, W - 20, 16), [UIFont systemFontOfSize:12], WHITE, NSTextAlignmentLeft); yy += 18; }
            T(@"✓ o ↩ torna al menu", CGRectMake(8, b.size.height - 18, W - 16, 14), [UIFont systemFontOfSize:10], GRAY, NSTextAlignmentLeft);
            break;
        }
        case OxiMenuPair: {
            // QR a sinistra (con margine bianco), tre passi a destra
            CGFloat q = MIN(140, b.size.height - 52), qx = 6, qy = 30;
            uint8_t mod[SFQR_MAX_SIZE * SFQR_MAX_SIZE]; int n = 0;
            NSData *u = [m.pairURL dataUsingEncoding:NSUTF8StringEncoding];
            if (u && SFQREncode(u.bytes, (int)u.length, mod, &n)) {
                [WHITE setFill]; CGContextFillRect(c, CGRectMake(qx, qy, q, q));
                CGFloat cell = floor(q / (n + 6)), off = floor((q - cell * n) / 2);
                [[UIColor blackColor] setFill];
                for (int yy = 0; yy < n; yy++) for (int xx = 0; xx < n; xx++)
                    if (mod[yy * n + xx]) CGContextFillRect(c, CGRectMake(qx + off + xx * cell, qy + off + yy * cell, cell, cell));
            } else {
                [RGB(40, 40, 40) setFill]; CGContextFillRect(c, CGRectMake(qx, qy, q, q));
                T(@"Wi-Fi non collegato:\nsegui i passi 1 e 2,\npoi il QR compare qui.", CGRectMake(qx + 8, qy + q / 2 - 24, q - 16, 48), [UIFont systemFontOfSize:11], WHITE, NSTextAlignmentCenter);
            }
            T([NSString stringWithFormat:@"PIN %@", m.pairPIN ?: @"-"], CGRectMake(qx, qy + q + 4, q, 16), [UIFont boldSystemFontOfSize:14], CYAN, NSTextAlignmentCenter);
            CGFloat tx = qx + q + 10, tw = W - tx - 6;
            UIFont *sf = [UIFont systemFontOfSize:11], *sb = [UIFont boldSystemFontOfSize:11];
            T(@"1. Hotspot sul telefono", CGRectMake(tx, 30, tw, 14), sb, WHITE, NSTextAlignmentLeft);
            T(@"banda 2,4 GHz\niPhone: Massimizza\ncompatibilità", CGRectMake(tx, 44, tw, 42), sf, GRAY, NSTextAlignmentLeft);
            T(@"2. iPod sulla rete", CGRectMake(tx, 92, tw, 14), sb, WHITE, NSTextAlignmentLeft);
            T(@"Impostazioni › Wi-Fi ›\nla rete del telefono", CGRectMake(tx, 106, tw, 28), sf, GRAY, NSTextAlignmentLeft);
            T(@"3. Inquadra il QR", CGRectMake(tx, 140, tw, 14), sb, WHITE, NSTextAlignmentLeft);
            T(@"con la fotocamera: la\nregia si apre già pronta", CGRectMake(tx, 154, tw, 28), sf, GRAY, NSTextAlignmentLeft);
            T(m.pairNote ?: @"Non serve internet.", CGRectMake(tx, 190, tw, 28), sb, m.pairNote ? YELLOW : GREEN, NSTextAlignmentLeft);
            T(@"✓ o ↩ torna al menu", CGRectMake(8, b.size.height - 18, W - 16, 14), [UIFont systemFontOfSize:10], GRAY, NSTextAlignmentLeft);
            break;
        }
        case OxiMenuEco: {
            T(@"Con il monitor similFranz sulla stessa rete Wi-Fi\nil saturimetro si aggancia da solo e i comandi\narrivano solo dalla console del monitor.", CGRectMake(10, 30, W - 20, 46), [UIFont systemFontOfSize:12], GRAY, NSTextAlignmentLeft);
            CGFloat yy = 84;
            for (NSString *line in m.ecoLines) { T(line, CGRectMake(10, yy, W - 20, 16), [UIFont systemFontOfSize:12], WHITE, NSTextAlignmentLeft); yy += 18; }
            T(@"✓ o ↩ torna al menu", CGRectMake(8, b.size.height - 18, W - 16, 14), [UIFont systemFontOfSize:10], GRAY, NSTextAlignmentLeft);
            break;
        }
        case OxiMenuConfirmReset: {
            T(@"Azzerare lo scenario e spegnere?", CGRectMake(12, 44, W - 24, 22), fb, WHITE, NSTextAlignmentLeft);
            T(@"Il paziente torna ai valori iniziali, tutti i sensori\nvengono scollegati e il monitor e il saturimetro\nsi spengono (come dal menu del monitor).", CGRectMake(12, 74, W - 24, 60), [UIFont systemFontOfSize:12], GRAY, NSTextAlignmentLeft);
            [RED setFill]; CGContextFillRect(c, CGRectMake(12, 150, W - 24, 34));
            T(@"✓  Azzera e spegni", CGRectMake(12, 158, W - 24, 20), fb, WHITE, NSTextAlignmentCenter);
            T(@"↩ annulla", CGRectMake(8, b.size.height - 18, W - 16, 14), [UIFont systemFontOfSize:10], GRAY, NSTextAlignmentLeft);
            break;
        }
        default: break;
    }
}
@end
