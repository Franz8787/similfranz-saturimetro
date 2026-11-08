#import <Foundation/Foundation.h>
@interface NetworkInfo : NSObject
+ (NSString *)wifiIPv4;      // indirizzo IPv4 dell'interfaccia Wi-Fi (en0), nil se assente
@end
