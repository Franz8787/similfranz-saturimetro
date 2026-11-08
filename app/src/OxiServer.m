#import "OxiServer.h"

@interface OxiServer () <NSNetServiceDelegate>
@end

@implementation OxiServer {
    LocalHTTPServer *_http; NSNetService *_svc; NSDictionary *_files;
    NSMutableDictionary *_failures, *_lockedUntil; NSTimeInterval _startTime;
}

- (instancetype)initWithState:(OxiLocalState *)state files:(NSDictionary *)files {
    if ((self = [super init])) {
        _state = state; _files = [files copy] ?: @{};
        _failures = [NSMutableDictionary dictionary]; _lockedUntil = [NSMutableDictionary dictionary];
        _clock = ^NSTimeInterval { return [NSProcessInfo processInfo].systemUptime; };
        _startTime = _clock(); _bonjour = YES;
    }
    return self;
}

- (BOOL)isRunning { return _http.running; }

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error {
    if (_http.running) return YES;
    __weak OxiServer *weak = self;
    _http = [[LocalHTTPServer alloc] initWithPort:port handler:^SLHTTPResponse *(SLHTTPRequest *req) { return [weak handle:req]; }];
    if (![_http start:error]) { _http = nil; return NO; }
    _port = port;
    if (_bonjour) {
        _svc = [[NSNetService alloc] initWithDomain:@"local." type:@"_http._tcp."
                                               name:[NSString stringWithFormat:@"similFranzSat %@", _state.deviceId] port:port];
        _svc.delegate = self; [_svc publish];
    }
    return YES;
}
- (void)stop { [_svc stop]; _svc = nil; [_http stop]; _http = nil; }
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict { NSLog(@"Bonjour non pubblicato: %@", errorDict); }

static SLHTTPResponse *Err(NSInteger status, NSString *msg) { return [SLHTTPResponse status:status json:@{ @"ok": @NO, @"error": msg }]; }
static BOOL ConstantTimeEquals(NSString *a, NSString *b) {
    NSData *da = [a dataUsingEncoding:NSUTF8StringEncoding], *db = [b dataUsingEncoding:NSUTF8StringEncoding];
    if (da.length != db.length || da.length == 0) return NO;
    const uint8_t *pa = da.bytes, *pb = db.bytes; uint8_t diff = 0;
    for (NSUInteger i = 0; i < da.length; i++) diff |= pa[i] ^ pb[i];
    return diff == 0;
}

// nil = autorizzato; 5 PIN sbagliati in 60 s -> 30 s di blocco per quell'indirizzo
- (SLHTTPResponse *)checkAuth:(SLHTTPRequest *)req {
    NSString *ip = req.remoteAddress ?: @"?"; NSTimeInterval now = _clock();
    @synchronized (self) {
        NSNumber *until = _lockedUntil[ip];
        if (until && now < until.doubleValue) {
            SLHTTPResponse *r = Err(429, @"too many failed attempts, retry later");
            r.extraHeaders = @{ @"Retry-After": [NSString stringWithFormat:@"%.0f", ceil(until.doubleValue - now)] };
            return r;
        }
        NSString *token = req.headers[@"x-simulafranz-token"];
        if (token && _pin.length && ConstantTimeEquals(token, _pin)) {
            [_failures removeObjectForKey:ip]; _lastClientAt = now;
            if (req.headers[@"x-simulafranz-pair"]) _pairedAt = now;      // console appena aperta dal QR dell'iPod
            return nil;
        }
        NSMutableArray *f = _failures[ip] ?: [NSMutableArray array];
        [f addObject:@(now)];
        NSMutableArray *keep = [NSMutableArray array];
        for (NSNumber *t in f) if (now - t.doubleValue <= 60) [keep addObject:t];
        _failures[ip] = keep;
        if (keep.count >= 5) { _lockedUntil[ip] = @(now + 30); [_failures removeObjectForKey:ip]; }
    }
    return Err(401, @"missing or invalid X-SimulaFranz-Token");
}

- (SLHTTPResponse *)okWithState {
    NSDictionary *st = [_state stateDictionary];
    return [SLHTTPResponse status:200 json:@{ @"ok": @YES, @"state": st, @"revision": st[@"revision"], @"error": [NSNull null] }];
}
- (SLHTTPResponse *)linkedResponse {
    NSString *url = self.monitorURL;
    if (!url) return nil;
    return [SLHTTPResponse status:409 json:@{ @"ok": @NO, @"error": @"linked to monitor: use the monitor console", @"monitor_url": url }];
}

- (SLHTTPResponse *)handle:(SLHTTPRequest *)req {
    NSString *m = req.method, *p = req.path;
    if ([p isEqualToString:@"/"] || [p isEqualToString:@"/index.html"]) {
        if (![m isEqualToString:@"GET"] && ![m isEqualToString:@"HEAD"]) return Err(405, @"method not allowed");
        NSData *d = _files[@"index.html"];
        if (!d) return Err(404, @"console file missing from app bundle");
        return [SLHTTPResponse status:200 type:@"text/html; charset=utf-8" data:d];
    }
    if ([p isEqualToString:@"/api/v1/health"]) {
        if (![m isEqualToString:@"GET"]) return Err(405, @"method not allowed");
        NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"dev";
        return [SLHTTPResponse status:200 json:@{
            @"ok": @YES, @"service": @"SimulaFranz_Saturimetro", @"device_id": _state.deviceId, @"device_type": @"oximeter",
            @"version": ver, @"api": @"v1", @"uptime_s": @((NSInteger)(_clock() - _startTime)), @"auth": @"X-SimulaFranz-Token",
            @"mode": self.monitorURL ? @"linked" : @"standalone", @"monitor_url": self.monitorURL ?: [NSNull null],
            @"commands": [OxiLocalState supportedCommands] }];
    }
    if ([p isEqualToString:@"/api/v1/state"]) {
        if (![m isEqualToString:@"GET"]) return Err(405, @"method not allowed");
        SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
        return [self linkedResponse] ?: [self okWithState];
    }
    if ([p isEqualToString:@"/api/v1/command"]) {
        if (![m isEqualToString:@"POST"]) return Err(405, @"method not allowed");
        SLHTTPResponse *deny = [self checkAuth:req]; if (deny) return deny;
        SLHTTPResponse *linked = [self linkedResponse]; if (linked) return linked;
        NSString *ct = [req.headers[@"content-type"] lowercaseString] ?: @"";
        if (![ct hasPrefix:@"application/json"]) return Err(400, @"Content-Type must be application/json");
        id json = req.body.length ? [NSJSONSerialization JSONObjectWithData:req.body options:0 error:NULL] : nil;
        if (![json isKindOfClass:[NSDictionary class]]) return Err(400, @"body must be a valid JSON object");
        NSString *err = nil;
        if (![_state applyCommand:json error:&err]) return Err(400, err ?: @"invalid command");
        return [self okWithState];
    }
    return Err(404, @"not found");
}
@end
