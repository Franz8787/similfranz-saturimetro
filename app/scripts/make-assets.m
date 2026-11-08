// Genera icona (57/114 px) e immagine di avvio (640x960) con AppKit, output in assets/
#import <AppKit/AppKit.h>
static NSColor *RGB(int r, int g, int b) { return [NSColor colorWithSRGBRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }
static NSBitmapImageRep *Canvas(NSInteger w, NSInteger h) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    rep.size = NSMakeSize(w, h); return rep;
}
static void Save(NSBitmapImageRep *rep, NSString *path) { [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES]; printf("  %s\n", path.lastPathComponent.UTF8String); }
static void Icon(NSInteger px, NSString *path) {
    NSBitmapImageRep *rep = Canvas(px, px);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    CGFloat s = px / 57.0;
    // scocca bianca arrotondata, schermo nero con valore verde e onda ciano, tastiera blu
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, px, px) xRadius:10 * s yRadius:10 * s];
    [RGB(240, 240, 238) setFill]; [body fill];
    NSRect scr = NSMakeRect(7 * s, 24 * s, 43 * s, 27 * s);
    [[NSColor blackColor] setFill]; [[NSBezierPath bezierPathWithRoundedRect:scr xRadius:2 * s yRadius:2 * s] fill];
    NSDictionary *a = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:15 * s], NSForegroundColorAttributeName: RGB(72, 235, 90) };
    [@"98" drawAtPoint:NSMakePoint(10 * s, 32 * s) withAttributes:a];
    NSBezierPath *w = [NSBezierPath bezierPath];
    for (int i = 0; i <= 40; i++) { CGFloat x = (CGFloat)i / 40, ph = fmod(x * 2, 1.0);
        CGFloat y = ph < .2 ? sin(ph / .2 * M_PI / 2) : exp(-(ph - .2) / .3);
        NSPoint p = NSMakePoint(scr.origin.x + 3 * s + x * (scr.size.width - 6 * s), scr.origin.y + 3 * s + y * 6 * s);
        if (i == 0) [w moveToPoint:p]; else [w lineToPoint:p]; }
    [RGB(80, 220, 255) setStroke]; w.lineWidth = 1.5 * s; [w stroke];
    NSRect plate = NSMakeRect(22 * s, 6 * s, 13 * s, 15 * s);
    [RGB(44, 108, 182) setFill]; [[NSBezierPath bezierPathWithRoundedRect:plate xRadius:2.5 * s yRadius:2.5 * s] fill];
    [RGB(92, 158, 224) setFill];
    for (NSValue *v in @[[NSValue valueWithRect:NSMakeRect(8 * s, 11 * s, 8 * s, 8 * s)], [NSValue valueWithRect:NSMakeRect(40 * s, 11 * s, 8 * s, 8 * s)]])
        [[NSBezierPath bezierPathWithRoundedRect:v.rectValue xRadius:2 * s yRadius:2 * s] fill];
    [NSGraphicsContext restoreGraphicsState];
    Save(rep, path);
}
static void Launch(NSString *path) {
    NSBitmapImageRep *rep = Canvas(640, 960);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [[NSColor blackColor] setFill]; NSRectFill(NSMakeRect(0, 0, 640, 960));
    NSDictionary *a = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:40], NSForegroundColorAttributeName: [NSColor whiteColor] };
    NSString *t = @"SimulaFranz_Saturimetro"; NSSize sz = [t sizeWithAttributes:a];
    [t drawAtPoint:NSMakePoint((640 - sz.width) / 2, 520) withAttributes:a];
    NSDictionary *b = @{ NSFontAttributeName: [NSFont systemFontOfSize:20], NSForegroundColorAttributeName: RGB(150, 155, 160) };
    t = @"SIMULAZIONE · NON PER USO CLINICO"; sz = [t sizeWithAttributes:b];
    [t drawAtPoint:NSMakePoint((640 - sz.width) / 2, 480) withAttributes:b];
    [NSGraphicsContext restoreGraphicsState];
    Save(rep, path);
}
int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *out = argc > 1 ? @(argv[1]) : @"assets";
    Icon(57, [out stringByAppendingPathComponent:@"Icon.png"]);
    Icon(114, [out stringByAppendingPathComponent:@"Icon@2x.png"]);
    Launch([out stringByAppendingPathComponent:@"Default@2x.png"]);
    return 0;
} }
