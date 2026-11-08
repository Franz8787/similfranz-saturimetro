// SimulaFranz_Saturimetro — generatore della curva pletismografica SIMULATA e dei battiti (per il tono del polso).
// Foundation + libm: testabile su macOS. Battiti programmati nel tempo dalla frequenza del polso del paziente;
// l'onda è funzione continua del tempo (niente immagini).
#import <Foundation/Foundation.h>
#import "OxiState.h"

@interface OxiEngine : NSObject
- (instancetype)initWithSeed:(unsigned int)seed;
- (void)updateWithPatient:(OxiPatient *)p signal:(OxiSignal)sig;
// Le query devono avvenire con tempi non decrescenti.
- (double)plethAt:(NSTimeInterval)t;                   // ~0..1 (linea piatta = 0)
- (NSTimeInterval)lastPerfusedBeatAtOrBefore:(NSTimeInterval)t;   // istante dell'ultimo polso perfuso (<= t), -1 se nessuno
- (double)amplitude;                                   // ampiezza del polso 0..1 (barra laterale)
@end
