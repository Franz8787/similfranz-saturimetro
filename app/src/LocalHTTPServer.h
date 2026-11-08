// SimulaFranz_Monitor — server HTTP/1.1 minimale (socket BSD + GCD), compatibile iOS 6+.
// - Una richiesta per connessione (Connection: close), sufficiente per il polling.
// - Limiti: header 8 KB, body 16 KB, timeout 5 s, max 8 connessioni simultanee.
// - Gira su una coda seriale dedicata: non tocca mai il main thread.

#import <Foundation/Foundation.h>

@interface SLHTTPRequest : NSObject
@property (nonatomic, copy) NSString *method;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *headers; // chiavi minuscole
@property (nonatomic, copy) NSData *body;
@property (nonatomic, copy) NSString *remoteAddress;
@end

@interface SLHTTPResponse : NSObject
@property (nonatomic) NSInteger status;
@property (nonatomic, copy) NSString *contentType;
@property (nonatomic, copy) NSData *body;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *extraHeaders;
+ (instancetype)status:(NSInteger)status json:(id)object;
+ (instancetype)status:(NSInteger)status type:(NSString *)type data:(NSData *)data;
@end

typedef SLHTTPResponse *(^SLHTTPHandler)(SLHTTPRequest *request);

@interface LocalHTTPServer : NSObject
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

- (instancetype)initWithPort:(uint16_t)port handler:(SLHTTPHandler)handler;
- (BOOL)start:(NSError **)error;
- (void)stop;
@end
