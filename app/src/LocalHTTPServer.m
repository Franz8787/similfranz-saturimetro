#import "LocalHTTPServer.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static const NSUInteger kMaxHeaderBytes = 8 * 1024;
static const NSUInteger kMaxBodyBytes   = 16 * 1024;
static const int64_t    kTimeoutNs      = 5 * NSEC_PER_SEC;
static const NSUInteger kMaxConnections = 8;

@implementation SLHTTPRequest
@end

@implementation SLHTTPResponse
+ (instancetype)status:(NSInteger)status json:(id)object {
    NSData *d = [NSJSONSerialization dataWithJSONObject:object options:0 error:NULL] ?: [NSData data];
    return [self status:status type:@"application/json; charset=utf-8" data:d];
}
+ (instancetype)status:(NSInteger)status type:(NSString *)type data:(NSData *)data {
    SLHTTPResponse *r = [SLHTTPResponse new];
    r.status = status; r.contentType = type; r.body = data ?: [NSData data];
    return r;
}
@end

static NSString *SLReason(NSInteger s) {
    switch (s) {
        case 200: return @"OK"; case 204: return @"No Content";
        case 400: return @"Bad Request"; case 401: return @"Unauthorized";
        case 404: return @"Not Found"; case 405: return @"Method Not Allowed";
        case 408: return @"Request Timeout"; case 409: return @"Conflict";
        case 413: return @"Payload Too Large"; case 429: return @"Too Many Requests";
        case 431: return @"Request Header Fields Too Large";
        case 503: return @"Service Unavailable";
        default:  return s < 400 ? @"OK" : @"Error";
    }
}

#pragma mark - Connessione

@class LocalHTTPServer;
@interface SLHTTPConnection : NSObject
- (instancetype)initWithFD:(int)fd remote:(NSString *)remote queue:(dispatch_queue_t)q
                   handler:(SLHTTPHandler)h onClose:(void (^)(SLHTTPConnection *))onClose;
- (void)startReading;
- (void)close;
@end

@implementation SLHTTPConnection {
    int _fd;
    NSString *_remote;
    dispatch_queue_t _queue;
    dispatch_source_t _readSource;
    SLHTTPHandler _handler;
    void (^_onClose)(SLHTTPConnection *);
    NSMutableData *_buffer;
    NSInteger _headerEnd;       // indice fine header (dopo \r\n\r\n), -1 se non ancora
    NSUInteger _contentLength;
    BOOL _closed, _responded;
}

- (instancetype)initWithFD:(int)fd remote:(NSString *)remote queue:(dispatch_queue_t)q
                   handler:(SLHTTPHandler)h onClose:(void (^)(SLHTTPConnection *))onClose {
    if ((self = [super init])) {
        _fd = fd; _remote = [remote copy]; _queue = q; _handler = h; _onClose = [onClose copy];
        _buffer = [NSMutableData dataWithCapacity:1024];
        _headerEnd = -1;
    }
    return self;
}

- (void)startReading {
    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)_fd, 0, _queue);
    __weak SLHTTPConnection *weakSelf = self;
    int fd = _fd;
    dispatch_source_set_event_handler(_readSource, ^{ [weakSelf readAvailable]; });
    dispatch_source_set_cancel_handler(_readSource, ^{ close(fd); });   // unico punto di chiusura del socket
    dispatch_resume(_readSource);
    // timeout complessivo della richiesta (protezione da client lenti)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kTimeoutNs), _queue, ^{
        SLHTTPConnection *s = weakSelf;
        if (s && !s->_closed && !s->_responded) [s respond:[SLHTTPResponse status:408 json:@{@"ok": @NO, @"error": @"request timeout"}]];
    });
}

- (void)readAvailable {
    if (_closed || _responded) return;
    uint8_t buf[4096];
    ssize_t n = read(_fd, buf, sizeof buf);
    if (n == 0) { [self close]; return; }
    if (n < 0) { if (errno != EAGAIN && errno != EINTR) [self close]; return; }
    [_buffer appendBytes:buf length:(NSUInteger)n];

    if (_headerEnd < 0) {
        NSData *sep = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        NSRange r = [_buffer rangeOfData:sep options:0 range:NSMakeRange(0, _buffer.length)];
        if (r.location == NSNotFound) {
            if (_buffer.length > kMaxHeaderBytes)
                [self respond:[SLHTTPResponse status:431 json:@{@"ok": @NO, @"error": @"headers too large"}]];
            return;
        }
        _headerEnd = (NSInteger)(r.location + r.length);
        if ((NSUInteger)_headerEnd > kMaxHeaderBytes) {
            [self respond:[SLHTTPResponse status:431 json:@{@"ok": @NO, @"error": @"headers too large"}]];
            return;
        }
    }
    SLHTTPRequest *req = [self parseHeaders];
    if (!req) { [self respond:[SLHTTPResponse status:400 json:@{@"ok": @NO, @"error": @"malformed request"}]]; return; }
    if (_contentLength > kMaxBodyBytes) {
        [self respond:[SLHTTPResponse status:413 json:@{@"ok": @NO, @"error": @"payload too large"}]];
        return;
    }
    NSUInteger have = _buffer.length - (NSUInteger)_headerEnd;
    if (have < _contentLength) return;   // attendo il resto del body
    req.body = [_buffer subdataWithRange:NSMakeRange((NSUInteger)_headerEnd, _contentLength)];

    SLHTTPResponse *resp = nil;
    @try { resp = _handler(req); }
    @catch (NSException *e) { resp = nil; }
    if (!resp) resp = [SLHTTPResponse status:500 json:@{@"ok": @NO, @"error": @"internal error"}];
    [self respond:resp];
}

- (SLHTTPRequest *)parseHeaders {
    NSString *head = [[NSString alloc] initWithData:[_buffer subdataWithRange:NSMakeRange(0, (NSUInteger)_headerEnd)]
                                           encoding:NSISOLatin1StringEncoding];
    NSArray<NSString *> *lines = [head componentsSeparatedByString:@"\r\n"];
    if (lines.count < 1) return nil;
    NSArray<NSString *> *parts = [lines[0] componentsSeparatedByString:@" "];
    if (parts.count != 3 || ![parts[2] hasPrefix:@"HTTP/1."]) return nil;
    NSString *target = parts[1];
    if (![target hasPrefix:@"/"] || target.length > 1024) return nil;

    SLHTTPRequest *req = [SLHTTPRequest new];
    req.method = [parts[0] uppercaseString];
    NSRange q = [target rangeOfString:@"?"];
    req.path  = q.location == NSNotFound ? target : [target substringToIndex:q.location];
    req.query = q.location == NSNotFound ? @"" : [target substringFromIndex:q.location + 1];
    req.remoteAddress = _remote;

    NSMutableDictionary *h = [NSMutableDictionary dictionary];
    for (NSUInteger i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        if (line.length == 0) continue;
        NSRange c = [line rangeOfString:@":"];
        if (c.location == NSNotFound) return nil;
        NSString *k = [[line substringToIndex:c.location] lowercaseString];
        NSString *v = [[line substringFromIndex:c.location + 1]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        h[k] = v;
    }
    req.headers = h;
    NSString *cl = h[@"content-length"];
    if (cl) {
        NSScanner *sc = [NSScanner scannerWithString:cl];
        long long len = -1;
        if (![sc scanLongLong:&len] || !sc.isAtEnd || len < 0) return nil;
        _contentLength = (NSUInteger)MIN(len, (long long)kMaxBodyBytes + 1);
    } else {
        _contentLength = 0;
    }
    if (h[@"transfer-encoding"]) return nil;   // chunked non supportato
    return req;
}

- (void)respond:(SLHTTPResponse *)resp {
    if (_closed || _responded) return;
    _responded = YES;

    NSMutableString *head = [NSMutableString stringWithFormat:@"HTTP/1.1 %ld %@\r\n", (long)resp.status, SLReason(resp.status)];
    [head appendFormat:@"Content-Type: %@\r\n", resp.contentType ?: @"text/plain"];
    [head appendFormat:@"Content-Length: %lu\r\n", (unsigned long)resp.body.length];
    [head appendString:@"Connection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n"];
    [resp.extraHeaders enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        [head appendFormat:@"%@: %@\r\n", k, v];
    }];
    [head appendString:@"\r\n"];
    NSMutableData *out = [[head dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    [out appendData:resp.body];

    // scrittura bloccante con timeout di invio (su coda di rete, mai sul main thread)
    int flags = fcntl(_fd, F_GETFL, 0);
    fcntl(_fd, F_SETFL, flags & ~O_NONBLOCK);
    struct timeval tv = { 5, 0 };
    setsockopt(_fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    const uint8_t *p = out.bytes; size_t left = out.length;
    while (left > 0) {
        ssize_t w = write(_fd, p, left);
        if (w < 0) { if (errno == EINTR) continue; break; }
        p += w; left -= (size_t)w;
    }
    [self close];
}

- (void)close {
    if (_closed) return;
    _closed = YES;
    shutdown(_fd, SHUT_RDWR);
    if (_readSource) { dispatch_source_cancel(_readSource); _readSource = nil; }  // chiude il fd
    else close(_fd);
    if (_onClose) _onClose(self);
    _onClose = nil;
}
@end

#pragma mark - Server

@implementation LocalHTTPServer {
    SLHTTPHandler _handler;
    dispatch_queue_t _queue;
    dispatch_source_t _acceptSource;
    int _listenFD;
    NSMutableSet<SLHTTPConnection *> *_connections;
}

- (instancetype)initWithPort:(uint16_t)port handler:(SLHTTPHandler)handler {
    if ((self = [super init])) {
        _port = port; _handler = [handler copy];
        _queue = dispatch_queue_create("it.simulafranz.saturimetro.http", DISPATCH_QUEUE_SERIAL);
        _listenFD = -1;
        _connections = [NSMutableSet set];
    }
    return self;
}

- (NSError *)posixError:(NSString *)what {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"HTTP server %@: %s", what, strerror(errno)]}];
}

- (BOOL)start:(NSError **)error {
    if (_running) return YES;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { if (error) *error = [self posixError:@"socket"]; return NO; }
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof addr);
    addr.sin_len = sizeof addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(_port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) < 0 || listen(fd, 16) < 0) {
        if (error) *error = [self posixError:@"bind/listen"];
        close(fd);
        return NO;
    }
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    _listenFD = fd;

    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, _queue);
    __weak LocalHTTPServer *weakSelf = self;
    dispatch_source_set_event_handler(_acceptSource, ^{ [weakSelf acceptConnections]; });
    dispatch_source_set_cancel_handler(_acceptSource, ^{ close(fd); });
    dispatch_resume(_acceptSource);
    _running = YES;
    return YES;
}

- (void)acceptConnections {
    for (;;) {
        struct sockaddr_in peer; socklen_t len = sizeof peer;
        int c = accept(_listenFD, (struct sockaddr *)&peer, &len);
        if (c < 0) return;   // EAGAIN: nessun'altra connessione in coda
        int yes = 1;
        setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof yes);
        setsockopt(c, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof yes);
        fcntl(c, F_SETFL, fcntl(c, F_GETFL, 0) | O_NONBLOCK);
        char ip[INET_ADDRSTRLEN] = "?";
        inet_ntop(AF_INET, &peer.sin_addr, ip, sizeof ip);

        if (_connections.count >= kMaxConnections) {
            static const char busy[] = "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
            fcntl(c, F_SETFL, fcntl(c, F_GETFL, 0) & ~O_NONBLOCK);
            write(c, busy, sizeof busy - 1);
            close(c);
            continue;
        }
        __weak LocalHTTPServer *weakSelf = self;
        SLHTTPConnection *conn = [[SLHTTPConnection alloc] initWithFD:c remote:@(ip) queue:_queue handler:_handler
                                                              onClose:^(SLHTTPConnection *closed) {
            LocalHTTPServer *s = weakSelf;
            if (s) [s->_connections removeObject:closed];
        }];
        [_connections addObject:conn];
        [conn startReading];
    }
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    dispatch_sync(_queue, ^{
        if (self->_acceptSource) { dispatch_source_cancel(self->_acceptSource); self->_acceptSource = nil; }
        self->_listenFD = -1;
        for (SLHTTPConnection *c in [self->_connections copy]) [c close];
        [self->_connections removeAllObjects];
    });
}

- (void)dealloc { [self stop]; }
@end
