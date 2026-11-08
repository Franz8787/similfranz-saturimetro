// SimulaFranz_Saturimetro — fronte del dispositivo (scocca bianca) e tastiera a sei tasti da saturimetro palmare:
//   ↩ (indietro)   ▲   ⏻ (accensione, con LED verde)
//                   ✓
//   🔕 (silenzia)  ▼   ≡ (menu)
// Icone disegnate in vettoriale (niente glifi emoji). Rilievo 3D e animazione di pressione.
#import <UIKit/UIKit.h>

@interface OxiKey : UIControl
@property (nonatomic, copy) NSString *glyph;     // "back" "up" "down" "ok" "power" "mute" "menu"
@property (nonatomic) BOOL plate;                // YES = segmento della piastra centrale (▲ ✓ ▼), NO = tasto laterale
@end

@interface OxiKeypad : UIView
@property (nonatomic) BOOL powerLed;             // LED verde accanto al tasto di accensione
@property (nonatomic, copy) void (^onKeyDown)(NSString *key);
@property (nonatomic, copy) void (^onKeyUp)(NSString *key, BOOL inside);
- (OxiKey *)keyNamed:(NSString *)name;
- (void)pressKey:(NSString *)name;               // pressione simulata (autotest / verifica da Mac)
@end
