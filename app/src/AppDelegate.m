// SimulaFranz_Saturimetro — avvio app e URL di verifica (simulafranz-saturimetro://shot|tap|selftest)
#import "AppDelegate.h"
#import "OxiViewController.h"
#import "SFLog.h"

@implementation AppDelegate {
    OxiViewController *_vc;
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"sf_port": @8080, @"sf_host": @"", @"sf_pin": @"", @"sf_mode": @"auto", @"sf_local_port": @8080, @"sf_local_pin": @"" }];
    SFLog(@"avvio SimulaFranz_Saturimetro %@ su iOS %@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], [[UIDevice currentDevice] systemVersion]);
    application.idleTimerDisabled = YES;                       // lo schermo resta acceso durante la simulazione
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    _vc = [OxiViewController new];
    self.window.rootViewController = _vc;
    [self.window makeKeyAndVisible];
    return YES;
}
- (void)applicationDidBecomeActive:(UIApplication *)application { application.idleTimerDisabled = YES; }
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url sourceApplication:(NSString *)src annotation:(id)ann {
    NSString *host = url.host ?: @"";
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    for (NSString *kv in [url.query componentsSeparatedByString:@"&"]) {
        NSRange r = [kv rangeOfString:@"="];
        if (r.location != NSNotFound) q[[kv substringToIndex:r.location]] = [[kv substringFromIndex:r.location + 1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    if ([host isEqualToString:@"tap"] && q[@"key"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [_vc debugTap:q[@"key"]]; });
    } else if ([host isEqualToString:@"shot"]) {
        NSString *name = q[@"name"] ?: @"shot";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [_vc saveShot:name]; });
    } else if ([host isEqualToString:@"selftest"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [_vc runSelfTest]; });
    }
    return YES;
}
@end
