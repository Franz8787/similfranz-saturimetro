#import "NetworkInfo.h"
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>
@implementation NetworkInfo
+ (NSString *)wifiIPv4 {
    struct ifaddrs *list = NULL; NSString *result = nil;
    if (getifaddrs(&list) != 0) return nil;
    for (struct ifaddrs *a = list; a; a = a->ifa_next) {
        if (!a->ifa_addr || a->ifa_addr->sa_family != AF_INET) continue;
        if (!(a->ifa_flags & IFF_UP) || (a->ifa_flags & IFF_LOOPBACK)) continue;
        if (strcmp(a->ifa_name, "en0") != 0) continue;
        char buf[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &((struct sockaddr_in *)a->ifa_addr)->sin_addr, buf, sizeof buf)) { result = @(buf); break; }
    }
    freeifaddrs(list);
    return result;
}
@end
