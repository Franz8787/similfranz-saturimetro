// similFranz Saturimetro — aggiornamento dell'app dal telefono, senza Mac.
// La console (sul telefono) scarica il pacchetto .deb della nuova versione da GitHub e lo invia all'iPod
// (POST /api/v1/update, protetto dal PIN). Qui il pacchetto viene CONTROLLATO (deve essere un .deb di questa app,
// per iPhoneOS) e consegnato all'aiutante di installazione, che gira come root e reinstalla l'app con dpkg.
// Foundation + zlib: testabile su macOS.
#import <Foundation/Foundation.h>

extern NSString *const OxiUpdatePackage;     // "it.simulafranz.saturimetro"
extern NSString *const OxiUpdateDebPath;     // dove l'app lascia il pacchetto per l'aiutante
extern NSString *const OxiUpdateHelperPath;  // aiutante di installazione (setuid root, installato dal pacchetto)

@interface OxiUpdate : NSObject
// Campi del file "control" di un .deb (Package, Version, Architecture, …) oppure nil con l'errore leggibile.
+ (NSDictionary<NSString *, NSString *> *)inspectDeb:(NSData *)deb error:(NSString **)error;
// Controlla il pacchetto, lo salva e avvia l'aiutante (che chiude e riapre l'app). Ritorna la versione o nil.
+ (NSString *)installDeb:(NSData *)deb error:(NSString **)error;
// L'aiutante è presente e può installare (file setuid root)
+ (BOOL)installerAvailable;
// Confronto di versioni "0.3.10" > "0.3.9": -1, 0, 1
+ (NSComparisonResult)compareVersion:(NSString *)a to:(NSString *)b;
@end
