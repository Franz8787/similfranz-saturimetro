// SimulaFranz_Saturimetro — client HTTP del monitor (SimulaFranz_Monitor sull'iPad):
// interroga /api/v1/state ogni 500 ms e invia i comandi del dispositivo. Trova il monitor con Bonjour
// (servizio "_http._tcp." chiamato "SimulaFranz_Monitor …") oppure usa l'host delle Impostazioni.
#import <Foundation/Foundation.h>

@interface OxiClient : NSObject
@property (nonatomic, copy) NSString *host;          // vuoto = cerca con Bonjour
@property (nonatomic) NSUInteger port;
@property (nonatomic, copy) NSString *pin;
@property (nonatomic, readonly) BOOL linked;         // ultima richiesta riuscita da meno di 6 s
@property (nonatomic, readonly) NSTimeInterval secondsSinceOK;   // -1 = mai riuscita
@property (nonatomic, readonly, copy) NSString *activeHost;   // host in uso (impostato o trovato)
@property (nonatomic, readonly, copy) NSString *lastError;
@property (nonatomic, copy) void (^onState)(NSDictionary *state);   // chiamato sul main thread
@property (nonatomic, copy) void (^onLink)(BOOL linked);
- (void)start;
- (void)stop;
- (void)sendCommand:(NSString *)name value:(id)value;
@end
