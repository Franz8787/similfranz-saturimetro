#import "OxiBatteryView.h"
@implementation OxiBatteryView
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; _level = 1; _tint = [UIColor blueColor]; } return self; }
- (void)setLevel:(float)l { _level = l; [self setNeedsDisplay]; }
- (void)setCharging:(BOOL)c { _charging = c; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    CGRect body = CGRectMake(0.5, 0.5, b.size.width - 3.5, b.size.height - 1);     // corpo + polo a destra (proporzioni iOS: ~2.6:1)
    CGRect pole = CGRectMake(CGRectGetMaxX(body), CGRectGetMidY(body) - 2, 2.5, 4);
    [_tint setStroke]; [_tint setFill];
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:body cornerRadius:3]; p.lineWidth = 1; [p stroke];
    [[UIBezierPath bezierPathWithRoundedRect:pole cornerRadius:1] fill];
    float lv = MAX(0, MIN(1, _level));
    UIColor *fill = lv > 0.5 ? [UIColor colorWithRed:0.30 green:0.80 blue:0.40 alpha:1] : lv > 0.2 ? [UIColor colorWithRed:0.98 green:0.72 blue:0.20 alpha:1] : [UIColor colorWithRed:0.93 green:0.30 blue:0.28 alpha:1];
    CGRect in = CGRectInset(body, 2, 2); in.size.width = MAX(0, in.size.width * lv);
    [fill setFill]; [[UIBezierPath bezierPathWithRoundedRect:in cornerRadius:2] fill];
    // percentuale dentro l'icona (testo scuro, leggibile sia sul pieno sia sul vuoto)
    NSString *t = [NSString stringWithFormat:@"%d%%", (int)lround(lv * 100)];
    UIFont *f = [UIFont boldSystemFontOfSize:9];
    CGSize sz = [t sizeWithFont:f];
    [[UIColor colorWithWhite:0.12 alpha:1] setFill];
    [t drawInRect:CGRectMake(CGRectGetMidX(body) - sz.width / 2 + (_charging ? 3.5 : 0), CGRectGetMidY(body) - sz.height / 2, sz.width, sz.height) withFont:f];
    if (_charging) {                                                              // fulmine vettoriale a sinistra
        CGFloat x = body.origin.x + 2.5, y = body.origin.y + 2, h = body.size.height - 4;
        UIBezierPath *bolt = [UIBezierPath bezierPath];
        [bolt moveToPoint:CGPointMake(x + 3.5, y)]; [bolt addLineToPoint:CGPointMake(x, y + h * 0.58)]; [bolt addLineToPoint:CGPointMake(x + 2.6, y + h * 0.58)];
        [bolt addLineToPoint:CGPointMake(x + 1.6, y + h)]; [bolt addLineToPoint:CGPointMake(x + 5.4, y + h * 0.40)]; [bolt addLineToPoint:CGPointMake(x + 2.8, y + h * 0.40)]; [bolt closePath];
        [[UIColor colorWithWhite:0.12 alpha:1] setFill]; [bolt fill];
        CGContextSetBlendMode(c, kCGBlendModeNormal);
    }
}
@end

@implementation OxiWifiView
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; _tint = [UIColor blueColor]; } return self; }
- (void)setState:(NSInteger)st { if (st != _state) { _state = st; [self setNeedsDisplay]; } }
- (void)drawRect:(CGRect)rect {
    CGRect b = self.bounds; CGPoint o = CGPointMake(CGRectGetMidX(b), CGRectGetMaxY(b) - 1.5);   // vertice in basso al centro
    UIColor *col = _state == 2 ? _tint : [UIColor colorWithWhite:0.70 alpha:1];
    [col setStroke]; [col setFill];
    [[UIBezierPath bezierPathWithArcCenter:o radius:1.3 startAngle:0 endAngle:2 * M_PI clockwise:YES] fill];
    CGFloat a0 = -M_PI / 2 - M_PI / 4.2, a1 = -M_PI / 2 + M_PI / 4.2;
    for (CGFloat r = 4; r <= 10.5; r += 3.25) { UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:o radius:r startAngle:a0 endAngle:a1 clockwise:YES]; arc.lineWidth = 1.6; arc.lineCapStyle = kCGLineCapRound; [arc stroke]; }
    if (_state == 0) {                                                           // niente rete: barra rossa
        UIBezierPath *bar = [UIBezierPath bezierPath]; [bar moveToPoint:CGPointMake(b.origin.x + 2, b.origin.y + 1)]; [bar addLineToPoint:CGPointMake(CGRectGetMaxX(b) - 2, CGRectGetMaxY(b) - 1)];
        bar.lineWidth = 1.8; [[UIColor colorWithRed:0.93 green:0.30 blue:0.28 alpha:1] setStroke]; [bar stroke];
    }
}
@end
