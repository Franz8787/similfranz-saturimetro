// SimulaFranz_Saturimetro — paziente SIMULATO "solo saturimetro" per l'uso autonomo (senza monitor iPad).
// Foundation pura, senza timer: i valori in transizione si calcolano dall'orologio quando vengono letti.
// Produce lo stesso JSON (sottoinsieme) di SimulaFranz_Monitor, così OxiPatient e la console web
// leggono il paziente locale esattamente come leggerebbero quello del monitor.
#import <Foundation/Foundation.h>

@interface OxiLocalState : NSObject
@property (nonatomic, copy) NSTimeInterval (^clock)(void);   // predefinito: systemUptime
@property (nonatomic, copy) NSString *deviceId;              // "saturimetro-01"
@property (nonatomic, readonly) NSUInteger revision;
@property (nonatomic, readonly) BOOL power;                  // comodo per il controller
+ (NSDictionary *)defaultLimits;                             // spo2_low 85, spo2_high 100, pr_low 30, pr_high 170
+ (NSArray *)supportedCommands;
- (BOOL)applyCommand:(NSDictionary *)cmd error:(NSString **)error;   // {"command":..., "value":...}
- (NSDictionary *)stateDictionary;                           // chiavi come /api/v1/state del monitor
- (void)reset;                                               // paziente iniziale, sensore staccato, dispositivo spento
@end
