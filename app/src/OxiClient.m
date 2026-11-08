#import "OxiClient.h"
#import "SFLog.h"
#include <arpa/inet.h>

@interface OxiClient () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@end

@implementation OxiClient {
    BOOL _running, _busy; NSTimeInterval _lastOK, _busySince; NSTimer *_timer;
    NSNetServiceBrowser *_browser; NSMutableArray *_services; NSString *_found; NSTimeInterval _lastSearch;
    NSOperationQueue *_queue; BOOL _reportedLink;
}
- (instancetype)init { if ((self = [super init])) { _port = 8080; _queue = [NSOperationQueue new]; _services = [NSMutableArray array]; } return self; }

- (BOOL)linked { return _lastOK > 0 && [NSDate timeIntervalSinceReferenceDate] - _lastOK < 6.0; }   // tollera qualche risposta lenta del Wi-Fi
- (NSString *)activeHost { return _host.length ? _host : _found; }
- (NSTimeInterval)secondsSinceOK { return _lastOK > 0 ? [NSDate timeIntervalSinceReferenceDate] - _lastOK : -1; }

- (void)start {
    if (_running) return;
    _running = YES;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self tick];
}
- (void)stop {
    _running = NO; [_timer invalidate]; _timer = nil;
    [_browser stop]; _browser = nil;
}

- (void)tick {
    if (!_running) return;
    BOOL l = self.linked;
    if (l != _reportedLink) { _reportedLink = l; if (_onLink) _onLink(l); }
    if (!self.activeHost.length || (!l && [NSDate timeIntervalSinceReferenceDate] - _lastSearch > 20)) [self search];
    if (_busy && [NSDate timeIntervalSinceReferenceDate] - _busySince > 6) _busy = NO;   // richiesta rimasta appesa
    if (!_busy && self.activeHost.length) [self poll];
}

- (NSMutableURLRequest *)request:(NSString *)path method:(NSString *)m body:(NSData *)body {
    NSString *url = [NSString stringWithFormat:@"http://%@:%lu%@", self.activeHost, (unsigned long)_port, path];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:4.0];
    r.HTTPMethod = m;
    [r setValue:_pin ?: @"" forHTTPHeaderField:@"X-SimulaFranz-Token"];
    [r setValue:@"oximeter" forHTTPHeaderField:@"X-SimulaFranz-Device"];
    if (body) { r.HTTPBody = body; [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; }
    return r;
}

- (void)handleResponse:(NSURLResponse *)resp data:(NSData *)data error:(NSError *)err {
    NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 0;
    if (err || code != 200) {
        NSString *e = err ? err.localizedDescription : [NSString stringWithFormat:@"HTTP %ld", (long)code];
        if (code == 401) e = @"PIN errato";
        if (![e isEqualToString:_lastError]) SFLog(@"richiesta fallita: %@ (%@:%lu)", e, self.activeHost, (unsigned long)_port);
        _lastError = e;
        return;
    }
    NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSDictionary *state = [json isKindOfClass:[NSDictionary class]] ? json[@"state"] : nil;
    if (![state isKindOfClass:[NSDictionary class]]) { _lastError = @"risposta non valida"; return; }
    _lastOK = [NSDate timeIntervalSinceReferenceDate]; _lastError = nil;
    if (_onState) _onState(state);
}

- (void)poll {
    _busy = YES; _busySince = [NSDate timeIntervalSinceReferenceDate];
    [NSURLConnection sendAsynchronousRequest:[self request:@"/api/v1/state" method:@"GET" body:nil] queue:_queue
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{ _busy = NO; [self handleResponse:resp data:data error:err]; });
    }];
}

- (void)sendCommand:(NSString *)name value:(id)value {
    if (!self.activeHost.length) return;
    NSDictionary *cmd = value ? @{ @"command": name, @"value": value } : @{ @"command": name };
    NSData *body = [NSJSONSerialization dataWithJSONObject:cmd options:0 error:NULL];
    SFLog(@"comando %@ %@", name, value);
    [NSURLConnection sendAsynchronousRequest:[self request:@"/api/v1/command" method:@"POST" body:body] queue:_queue
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleResponse:resp data:data error:err];
            if (_lastError) SFLog(@"comando %@ fallito: %@", name, _lastError);
        });
    }];
}

#pragma mark - Bonjour

- (void)search {
    _lastSearch = [NSDate timeIntervalSinceReferenceDate];
    [_browser stop];
    _browser = [NSNetServiceBrowser new]; _browser.delegate = self;
    [_browser searchForServicesOfType:@"_http._tcp." inDomain:@"local."];
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)b didFindService:(NSNetService *)svc moreComing:(BOOL)more {
    if (![svc.name hasPrefix:@"SimulaFranz_Monitor"]) return;
    [_services addObject:svc]; svc.delegate = self; [svc resolveWithTimeout:5];
}
- (void)netServiceDidResolveAddress:(NSNetService *)svc {
    for (NSData *d in svc.addresses) {
        const struct sockaddr *sa = d.bytes;
        if (sa->sa_family != AF_INET) continue;
        char buf[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &((const struct sockaddr_in *)sa)->sin_addr, buf, sizeof buf)) {
            NSString *h = @(buf);
            if (![h isEqualToString:_found] || svc.port != (NSInteger)_port) SFLog(@"Bonjour: monitor %@ a %@:%ld", svc.name, h, (long)svc.port);
            _found = h; if (svc.port > 0) _port = (NSUInteger)svc.port;
            break;
        }
    }
    [_services removeObject:svc];
}
- (void)netService:(NSNetService *)svc didNotResolve:(NSDictionary *)errorDict { [_services removeObject:svc]; }
@end
