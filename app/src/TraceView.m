#import "TraceView.h"
static const int kSub = 3, kGap = 12;
@implementation TraceView { float *_values; int _width, _cursor; NSTimeInterval _lastT, _lastScale; double _fraction; BOOL _hasTime; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.opaque = YES; self.backgroundColor = [UIColor blackColor]; self.contentMode = UIViewContentModeRedraw;
        _traceColor = [UIColor cyanColor]; _minValue = -0.05; _maxValue = 1.05; _sweepSpeed = 60; _minSpan = 0.25;
    }
    return self;
}
- (void)dealloc { free(_values); }
- (void)ensureBuffer {
    int w = (int)floor(self.bounds.size.width);
    if (w == _width && _values) return;
    free(_values); _width = MAX(w, 1); _values = malloc(sizeof(float) * (size_t)_width);
    for (int i = 0; i < _width; i++) _values[i] = NAN;
    _cursor = 0;
}
- (void)layoutSubviews { [super layoutSubviews]; [self ensureBuffer]; }
- (void)resetAtTime:(NSTimeInterval)t {
    [self ensureBuffer];
    for (int i = 0; i < _width; i++) _values[i] = NAN;
    _cursor = 0; _lastT = t; _fraction = 0; _hasTime = YES; [self setNeedsDisplay];
}
- (BOOL)advanceTo:(NSTimeInterval)t {
    [self ensureBuffer];
    if (!_hasTime) { _lastT = t; _hasTime = YES; return NO; }
    double dt = t - _lastT; if (dt <= 0) return NO;
    if (dt > 1.0) { _lastT = t - 1.0; dt = 1.0; }
    double px = dt * _sweepSpeed + _fraction; int n = (int)floor(px); _fraction = px - n;
    if (n <= 0) return NO;
    double spp = 1.0 / _sweepSpeed; NSTimeInterval tp = _lastT; int start = _cursor;
    for (int i = 0; i < n; i++) {
        double best = 0, bestAbs = -1;
        for (int k = 1; k <= kSub; k++) { double v = _sampler ? _sampler(tp + spp * k / kSub) : 0; if (fabs(v) > bestAbs) { bestAbs = fabs(v); best = v; } }
        tp += spp;
        _values[_cursor] = (float)best; _cursor = (_cursor + 1) % _width;
        for (int g = 0; g < kGap; g++) _values[(_cursor + g) % _width] = NAN;
    }
    _lastT = tp;
    if (_autoScale && t - _lastScale > 0.5) { _lastScale = t; [self rescale]; }
    int count = MIN(_width, n + kGap + 2), from = (start - 1 + _width) % _width;
    CGFloat h = self.bounds.size.height;
    if (from + count <= _width) [self setNeedsDisplayInRect:CGRectMake(from - 3, 0, count + 6, h)];
    else { int first = _width - from; [self setNeedsDisplayInRect:CGRectMake(from - 3, 0, first + 6, h)]; [self setNeedsDisplayInRect:CGRectMake(-3, 0, count - first + 6, h)]; }
    return YES;
}
- (void)rescale {
    double mn = INFINITY, mx = -INFINITY;
    for (int i = 0; i < _width; i++) { float v = _values[i]; if (!isnan(v)) { mn = MIN(mn, v); mx = MAX(mx, v); } }
    if (!isfinite(mn) || !isfinite(mx)) return;
    double span = MAX(mx - mn, _minSpan), cur = _maxValue - _minValue;
    if (mx > _maxValue || mn < _minValue || span < cur * 0.55) { double pad = span * 0.12; _minValue = mn - pad; _maxValue = mn - pad + span + 2 * pad; [self setNeedsDisplay]; }
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    [[UIColor blackColor] setFill]; CGContextFillRect(ctx, rect);
    if (!_values) return;
    double range = _maxValue - _minValue; if (range <= 0) range = 1;
    CGFloat h = self.bounds.size.height - 4, top = 2;
    CGContextSetStrokeColorWithColor(ctx, _traceColor.CGColor);
    CGContextSetLineWidth(ctx, 1.6); CGContextSetLineJoin(ctx, kCGLineJoinRound); CGContextSetLineCap(ctx, kCGLineCapRound);
    int x0 = MAX(0, (int)floor(CGRectGetMinX(rect)) - 2), x1 = MIN(_width, (int)ceil(CGRectGetMaxX(rect)) + 2);
    BOOL pen = NO;
    for (int x = x0; x < x1; x++) {
        float v = _values[x];
        if (isnan(v)) { pen = NO; continue; }
        double norm = MAX(-0.05, MIN(1.05, (v - _minValue) / range));
        CGFloat y = top + h * (CGFloat)(1.0 - norm);
        if (!pen) { CGContextMoveToPoint(ctx, x, y); pen = YES; } else CGContextAddLineToPoint(ctx, x, y);
    }
    CGContextStrokePath(ctx);
}
@end
