// SimulaFranz_Saturimetro — tracciato a "sweep" (cursore che avanza e cancella una fascia davanti), iOS 6.
#import <UIKit/UIKit.h>
@interface TraceView : UIView
@property (nonatomic, strong) UIColor *traceColor;
@property (nonatomic) double minValue, maxValue;      // scala verticale
@property (nonatomic) double sweepSpeed;              // punti al secondo
@property (nonatomic) BOOL autoScale;                 // scala continua (pleth)
@property (nonatomic) double minSpan;
@property (nonatomic, copy) double (^sampler)(NSTimeInterval t);
- (BOOL)advanceTo:(NSTimeInterval)t;                  // ritorna YES se ha ridisegnato
- (void)resetAtTime:(NSTimeInterval)t;
@end
