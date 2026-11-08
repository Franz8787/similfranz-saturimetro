#import "OxiKeypad.h"
#import <QuartzCore/QuartzCore.h>

static UIColor *RGB(int r, int g, int b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }

@implementation OxiKey
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) { self.opaque = NO; self.backgroundColor = [UIColor clearColor]; self.contentMode = UIViewContentModeRedraw; }
    return self;
}
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    [UIView animateWithDuration:h ? 0.05 : 0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.transform = h ? CGAffineTransformScale(CGAffineTransformMakeTranslation(0, 1), 0.96, 0.96) : CGAffineTransformIdentity; } completion:nil];
    [self setNeedsDisplay];
}
static void glyphPath(CGContextRef c, NSString *g, CGRect b) {
    CGFloat cx = CGRectGetMidX(b), cy = CGRectGetMidY(b), s = MIN(b.size.width, b.size.height) * 0.46;
    CGContextSetLineWidth(c, 2.6); CGContextSetLineCap(c, kCGLineCapRound); CGContextSetLineJoin(c, kCGLineJoinRound);
    if ([g isEqualToString:@"up"] || [g isEqualToString:@"down"]) {
        CGFloat d = [g isEqualToString:@"up"] ? -1 : 1;
        CGContextMoveToPoint(c, cx - s * 0.62, cy - d * s * 0.42); CGContextAddLineToPoint(c, cx, cy + d * s * 0.42); CGContextAddLineToPoint(c, cx + s * 0.62, cy - d * s * 0.42);
        CGContextClosePath(c); CGContextFillPath(c);
    } else if ([g isEqualToString:@"ok"]) {
        CGContextSetLineWidth(c, 3.4);
        CGContextMoveToPoint(c, cx - s * 0.62, cy + s * 0.02); CGContextAddLineToPoint(c, cx - s * 0.18, cy + s * 0.48); CGContextAddLineToPoint(c, cx + s * 0.66, cy - s * 0.5);
        CGContextStrokePath(c);
    } else if ([g isEqualToString:@"power"]) {
        CGContextSetLineWidth(c, 2.8);
        CGContextAddArc(c, cx, cy + s * 0.05, s * 0.62, -M_PI / 2 + 0.55, -M_PI / 2 - 0.55, 0); CGContextStrokePath(c);
        CGContextMoveToPoint(c, cx, cy - s * 0.72); CGContextAddLineToPoint(c, cx, cy - s * 0.02); CGContextStrokePath(c);
    } else if ([g isEqualToString:@"back"]) {
        // freccia che torna indietro: gambo che scende a destra, curva, punta verso sinistra
        CGContextMoveToPoint(c, cx + s * 0.55, cy - s * 0.45); CGContextAddLineToPoint(c, cx + s * 0.55, cy + s * 0.1);
        CGContextAddCurveToPoint(c, cx + s * 0.55, cy + s * 0.5, cx + s * 0.2, cy + s * 0.5, cx - s * 0.05, cy + s * 0.5);
        CGContextAddLineToPoint(c, cx - s * 0.55, cy + s * 0.5); CGContextStrokePath(c);
        CGContextMoveToPoint(c, cx - s * 0.2, cy + s * 0.12); CGContextAddLineToPoint(c, cx - s * 0.62, cy + s * 0.5); CGContextAddLineToPoint(c, cx - s * 0.2, cy + s * 0.88);
        CGContextStrokePath(c);
    } else if ([g isEqualToString:@"mute"]) {
        // campana con barra
        CGContextSetLineWidth(c, 2.2);
        CGContextMoveToPoint(c, cx - s * 0.6, cy + s * 0.35); CGContextAddLineToPoint(c, cx - s * 0.42, cy + s * 0.1);
        CGContextAddLineToPoint(c, cx - s * 0.42, cy - s * 0.2); CGContextAddArc(c, cx, cy - s * 0.2, s * 0.42, M_PI, 0, 0);
        CGContextAddLineToPoint(c, cx + s * 0.42, cy + s * 0.1); CGContextAddLineToPoint(c, cx + s * 0.6, cy + s * 0.35); CGContextClosePath(c); CGContextStrokePath(c);
        CGContextAddArc(c, cx, cy + s * 0.5, s * 0.16, 0, 2 * M_PI, 0); CGContextFillPath(c);
        CGContextSetLineWidth(c, 3.0);
        CGContextMoveToPoint(c, cx - s * 0.7, cy - s * 0.7); CGContextAddLineToPoint(c, cx + s * 0.7, cy + s * 0.7); CGContextStrokePath(c);
    } else if ([g isEqualToString:@"menu"]) {
        CGContextSetLineWidth(c, 3.0);
        for (int i = -1; i <= 1; i++) { CGContextMoveToPoint(c, cx - s * 0.6, cy + i * s * 0.42); CGContextAddLineToPoint(c, cx + s * 0.6, cy + i * s * 0.42); }
        CGContextStrokePath(c);
    }
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = CGRectInset(self.bounds, 1, 1);
    BOOL hi = self.highlighted;
    CGFloat r = _plate ? 7 : 9;
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:r];
    if (!_plate) {
        // tasto laterale: azzurro chiaro con riflesso in alto e ombra corta
        CGContextSaveGState(c);
        CGContextSetShadowWithColor(c, CGSizeMake(0, hi ? 0.5 : 1.6), hi ? 1 : 2.2, [UIColor colorWithWhite:0 alpha:0.35].CGColor);
        [(hi ? RGB(66, 128, 196) : RGB(92, 158, 224)) setFill]; [p fill];
        CGContextRestoreGState(c);
        CGContextSaveGState(c); [p addClip];
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat cols[8] = { 1, 1, 1, hi ? 0.08 : 0.30, 1, 1, 1, 0.0 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, cols, NULL, 2);
        CGContextDrawLinearGradient(c, g, CGPointMake(0, b.origin.y), CGPointMake(0, CGRectGetMidY(b)), 0);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
        CGContextRestoreGState(c);
        [[UIColor colorWithWhite:0 alpha:0.18] setStroke]; p.lineWidth = 1; [p stroke];
    } else {
        // segmento della piastra centrale: si scurisce quando premuto
        [(hi ? [UIColor colorWithWhite:0 alpha:0.22] : [UIColor clearColor]) setFill]; [p fill];
    }
    [[UIColor whiteColor] setFill]; [[UIColor whiteColor] setStroke];
    glyphPath(c, _glyph, CGRectInset(b, 6, 6));
}
@end

@implementation OxiKeypad {
    NSMutableDictionary *_keys; UIView *_plate; UIView *_led;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = YES; self.backgroundColor = [UIColor whiteColor];
        _keys = [NSMutableDictionary dictionary];
        [self build];
    }
    return self;
}
- (void)build {
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    // piastra centrale (▲ ✓ ▼): rettangolo blu arrotondato con rilievo
    CGFloat pw = 60, ph = MIN(156, H - 24), px = (W - pw) / 2, py = (H - ph) / 2;
    _plate = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, ph)];
    _plate.backgroundColor = RGB(44, 108, 182);
    _plate.layer.cornerRadius = 10;
    _plate.layer.shadowColor = [UIColor blackColor].CGColor; _plate.layer.shadowOpacity = 0.38; _plate.layer.shadowRadius = 2.2; _plate.layer.shadowOffset = CGSizeMake(0, 2);
    _plate.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_plate.bounds cornerRadius:10].CGPath;
    CAGradientLayer *g = [CAGradientLayer layer]; g.frame = _plate.bounds; g.cornerRadius = 10;
    g.colors = @[ (id)[UIColor colorWithWhite:1 alpha:0.28].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.04].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.14].CGColor ];
    g.locations = @[@0.0, @0.45, @1.0];
    [_plate.layer addSublayer:g];
    [self addSubview:_plate];
    CGFloat seg = ph / 3;
    [self key:@"up"   frame:CGRectMake(px, py, pw, seg) plate:YES];
    [self key:@"ok"   frame:CGRectMake(px, py + seg, pw, seg) plate:YES];
    [self key:@"down" frame:CGRectMake(px, py + 2 * seg, pw, seg) plate:YES];
    // tasti laterali
    CGFloat ks = 50, gapX = 22, leftX = px - gapX - ks, rightX = px + pw + gapX;
    CGFloat topY = py + 6, botY = py + ph - ks - 6;
    [self key:@"back"  frame:CGRectMake(leftX, topY, ks, ks) plate:NO];
    [self key:@"power" frame:CGRectMake(rightX, topY, ks, ks) plate:NO];
    [self key:@"mute"  frame:CGRectMake(leftX, botY, ks, ks) plate:NO];
    [self key:@"menu"  frame:CGRectMake(rightX, botY, ks, ks) plate:NO];
    // LED verde di accensione (sopra il tasto, a destra)
    _led = [[UIView alloc] initWithFrame:CGRectMake(rightX + ks - 4, topY - 9, 7, 7)];
    _led.layer.cornerRadius = 3.5; _led.backgroundColor = RGB(110, 120, 110); _led.layer.borderWidth = 0.5; _led.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.3].CGColor;
    [self addSubview:_led];
    // vite/fessure decorative? no: fronte pulito come il dispositivo reale
}
- (void)key:(NSString *)name frame:(CGRect)f plate:(BOOL)plate {
    OxiKey *k = [[OxiKey alloc] initWithFrame:f]; k.glyph = name; k.plate = plate;
    [k addTarget:self action:@selector(down:) forControlEvents:UIControlEventTouchDown];
    [k addTarget:self action:@selector(upInside:) forControlEvents:UIControlEventTouchUpInside];
    [k addTarget:self action:@selector(upOutside:) forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addSubview:k]; _keys[name] = k;
}
- (void)down:(OxiKey *)k { if (_onKeyDown) _onKeyDown(k.glyph); }
- (void)upInside:(OxiKey *)k { if (_onKeyUp) _onKeyUp(k.glyph, YES); }
- (void)upOutside:(OxiKey *)k { if (_onKeyUp) _onKeyUp(k.glyph, NO); }
- (OxiKey *)keyNamed:(NSString *)name { return _keys[name]; }
- (void)pressKey:(NSString *)name {
    OxiKey *k = _keys[name]; if (!k) return;
    k.highlighted = YES; if (_onKeyDown) _onKeyDown(name);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ k.highlighted = NO; if (_onKeyUp) _onKeyUp(name, YES); });
}
- (void)setPowerLed:(BOOL)on {
    _powerLed = on;
    _led.backgroundColor = on ? RGB(70, 230, 90) : RGB(110, 120, 110);
    _led.layer.shadowColor = RGB(70, 230, 90).CGColor; _led.layer.shadowOpacity = on ? 0.9 : 0; _led.layer.shadowRadius = 3; _led.layer.shadowOffset = CGSizeZero;
    _led.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:_led.bounds].CGPath;
}
- (void)drawRect:(CGRect)rect {
    // scocca: bianco leggermente caldo con lieve gradiente e bordo inferiore
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat cols[8] = { 0.96, 0.96, 0.95, 1, 0.90, 0.90, 0.89, 1 };
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, cols, NULL, 2);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(0, self.bounds.size.height), 0);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
}
@end
