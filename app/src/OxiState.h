// SimulaFranz_Saturimetro — modello del saturimetro palmare SIMULATO .
// Foundation pura: compilabile e testabile su macOS (tests/).
//
// Il paziente è quello del monitor (iPad): questo dispositivo legge lo stato via HTTP e decide
// da solo che cosa mostrare (ricerca del polso, "?", interferenza, allarmi) come farebbe un vero
// saturimetro collegato allo stesso paziente.
#import <Foundation/Foundation.h>

// Stato remoto (dall'API /api/v1/state del monitor) già interpretato
@interface OxiPatient : NSObject
@property (nonatomic) NSInteger spo2, pulseRate, heartRate, systolic;
@property (nonatomic) BOOL pulsePresent, signalValid, lowPerfusion, lowPerfFlag, cpr, running;
@property (nonatomic) NSInteger motion;                 // 0 fermo, 1 lieve, 2 marcato
@property (nonatomic, copy) NSString *rhythm;
@property (nonatomic) NSInteger delaySec;               // ritardo di comparsa del valore (impostato dall'istruttore)
// saturimetro (sotto-oggetto "oximeter")
@property (nonatomic) BOOL sensorConnected, cuffOccluded, remotePower;
@property (nonatomic) double sensorSince;               // s dal collegamento del sensore, -1 = scollegato
@property (nonatomic) NSInteger volume, mutedRemaining;
@property (nonatomic) NSInteger acquireSec;              // tempo di rilevamento dopo l'applicazione della sonda (0 = automatico 5-10 s)
@property (nonatomic, copy) NSDictionary *limits;       // spo2_low, spo2_high, pr_low, pr_high
@property (nonatomic) NSUInteger revision;
+ (instancetype)patientFromState:(NSDictionary *)state;   // nil se il JSON non è uno stato valido
- (NSInteger)limit:(NSString *)key;
@end

// Qualità del segnale "vista" dal saturimetro
typedef NS_ENUM(NSInteger, OxiSignal) {
    OxiSignalSensorOff = 0,   // sensore non applicato
    OxiSignalSearching,       // appena applicato: ricerca del polso (nessuna onda)
    OxiSignalAcquiring,       // onda presente, valore non ancora pronto
    OxiSignalNoPulse,         // nessun polso (arresto): onda piatta (o piccole onde da RCP)
    OxiSignalInterference,    // segnale assente (artefatto) o bracciale in misura sullo stesso braccio
    OxiSignalOK               // valore mostrabile (eventualmente con "?" per bassa perfusione)
};
OxiSignal OxiSignalFor(OxiPatient *p);

typedef NS_ENUM(NSInteger, OxiAlarmLevel) { OxiAlarmNone = 0, OxiAlarmLow, OxiAlarmMedium, OxiAlarmHigh };

// Esito della valutazione allarmi: livello massimo, messaggio principale e parametri violati
@interface OxiAlarmResult : NSObject
@property (nonatomic) OxiAlarmLevel level;
@property (nonatomic, copy) NSArray *messages;          // ordinati per priorità (italiano, maiuscolo)
@property (nonatomic) OxiAlarmLevel spo2Level, prLevel; // per far lampeggiare i valori
@property (nonatomic) BOOL spo2LowViolated, spo2HighViolated, prLowViolated, prHighViolated;
@end
// noPulseFor: secondi senza polso con sensore applicato (0 se non applicabile); searchFor: secondi di ricerca
OxiAlarmResult *OxiEvaluate(OxiPatient *p, OxiSignal sig, NSTimeInterval noPulseFor, NSTimeInterval searchFor);

// Frequenza del tono del polso in funzione della SpO2 (acuto = alta, grave = bassa)
double OxiBeepFrequency(NSInteger spo2);

// ---- Menu del dispositivo (tasti ▲ ▼ ✓ ↩) ----
typedef NS_ENUM(NSInteger, OxiMenuPage) { OxiMenuClosed = 0, OxiMenuMain, OxiMenuLimits, OxiMenuPulseVol, OxiMenuAlarmVol, OxiMenuInfo, OxiMenuConfirmReset, OxiMenuPair, OxiMenuEco, OxiMenuConnect };
typedef NS_ENUM(NSInteger, OxiMenuAction) { OxiMenuNoAction = 0, OxiMenuLimitsChanged, OxiMenuPulseVolChanged, OxiMenuAlarmVolChanged, OxiMenuResetScenario };

@interface OxiMenu : NSObject
@property (nonatomic, readonly) OxiMenuPage page;
@property (nonatomic, readonly) NSInteger cursor;            // voce selezionata
@property (nonatomic, readonly) BOOL editing;                // nella pagina limiti: valore in modifica
@property (nonatomic, copy) NSDictionary *limits;            // copia di lavoro (spo2_low, spo2_high, pr_low, pr_high)
@property (nonatomic) NSInteger pulseVolume;                 // 0..10 (locale)
@property (nonatomic) NSInteger alarmVolume;                 // 0..10 (condiviso con il controller: volume %/10)
@property (nonatomic, copy) NSArray *infoLines;
@property (nonatomic, copy) NSString *pairURL;               // indirizzo nel QR (nil = Wi-Fi assente)
@property (nonatomic, copy) NSString *pairPIN, *pairNote;    // PIN della web app; nota (es. collegato al monitor)
@property (nonatomic, copy) NSArray *ecoLines;               // pagina Ecosistema monitor: stato del collegamento
+ (NSArray *)mainItems;                                      // titoli delle voci del menu principale
+ (NSArray *)connectItems;                                   // sottomenu Collegamento
+ (NSArray *)limitKeys;                                      // ordine delle 4 voci della pagina limiti
+ (NSString *)limitTitle:(NSString *)key;
- (void)open;
- (void)openLimitsAt:(NSInteger)cursor;                      // pagina limiti direttamente (tocco sul valore)
- (void)close;
- (OxiMenuAction)key:(NSString *)key;                        // "up" "down" "ok" "back" -> azione da eseguire
@end
