// SimulaFranz_Saturimetro — log diagnostico su file (leggibile via SSH/USB):
//   /var/mobile/Library/Caches/SimulaFranz_Saturimetro.log  (max ~256 KB, poi ruota)
#import <Foundation/Foundation.h>
void SFLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
