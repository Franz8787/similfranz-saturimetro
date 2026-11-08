// Icona della batteria REALE dell'iPod per l'intestazione: livello, percentuale dentro l'icona, fulmine se in carica.
#import <UIKit/UIKit.h>
@interface OxiBatteryView : UIView
@property (nonatomic) float level;        // 0..1
@property (nonatomic) BOOL charging;
@property (nonatomic, strong) UIColor *tint;
@end

// Simbolo Wi-Fi (archi + punto) accanto alla batteria: 0 = niente rete (grigio barrato), 1 = rete ma nessuna regia collegata (grigio),
// 2 = regia collegata (web app o monitor che dialoga con il saturimetro): blu pieno
@interface OxiWifiView : UIView
@property (nonatomic) NSInteger state;
@property (nonatomic, strong) UIColor *tint;
@end
