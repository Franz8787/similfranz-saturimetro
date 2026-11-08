// SimulaFranz_Saturimetro — server interno per l'uso autonomo: API /api/v1 (stesso schema del monitor,
// sottoinsieme), console web ridotta (www/index.html), PIN con blocco anti-tentativi, annuncio Bonjour.
// Quando l'iPod è agganciato a un monitor, stato e comandi rispondono 409 con l'indirizzo del monitor.
#import <Foundation/Foundation.h>
#import "LocalHTTPServer.h"
#import "OxiLocalState.h"

@interface OxiServer : NSObject
@property (nonatomic, readonly) OxiLocalState *state;
@property (nonatomic, copy) NSString *pin;                       // PIN della web app locale
@property (nonatomic, copy) NSString *monitorURL;                // nil = autonomo; altrimenti "http://host:porta/" del monitor in uso
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) NSTimeInterval lastClientAt;     // ultima richiesta autenticata (orologio `clock`), 0 = mai
@property (nonatomic, readonly) NSTimeInterval pairedAt;         // ultima console aperta dal QR (header X-SimulaFranz-Pair), 0 = mai
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, copy) NSTimeInterval (^clock)(void);
@property (nonatomic) BOOL bonjour;                              // annuncia "similFranzSat <id>" (_http._tcp.)
- (instancetype)initWithState:(OxiLocalState *)state files:(NSDictionary *)files;   // files: nome -> NSData (index.html)
- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;
- (void)stop;
- (SLHTTPResponse *)handle:(SLHTTPRequest *)req;                 // esposto per i test
@end
