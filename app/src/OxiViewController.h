#import <UIKit/UIKit.h>
@interface OxiViewController : UIViewController
- (void)debugTap:(NSString *)key;          // "power_long", "power", "back", "up", "down", "ok", "mute", "menu"
- (void)saveShot:(NSString *)name;         // screenshot in Caches/shots/<name>.png (verifica da Mac)
- (void)runSelfTest;                       // sequenza automatica con screenshot e log
@end
