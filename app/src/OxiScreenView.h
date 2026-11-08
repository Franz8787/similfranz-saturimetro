// SimulaFranz_Saturimetro — display del saturimetro (nero): barra di stato, SpO2 grande, pletismo, polso, limiti, menu.
#import <UIKit/UIKit.h>
#import "OxiState.h"
@class TraceView;

@interface OxiScreenView : UIView
@property (nonatomic, readonly, strong) TraceView *trace;
@property (nonatomic) BOOL powered;
@property (nonatomic) double bootProgress;          // < 0 nessun avvio in corso, 0..1 schermata di avvio
@property (nonatomic, copy) NSString *spo2Text, *prText;
@property (nonatomic, copy) NSString *message;      // messaggio principale (barra di stato)
@property (nonatomic) OxiAlarmLevel messageLevel;
@property (nonatomic) OxiAlarmLevel spo2Flash, prFlash;   // valore in allarme (riquadro lampeggiante)
@property (nonatomic) BOOL flashOn;                 // fase del lampeggio
@property (nonatomic) NSInteger spo2Low, spo2High, prLow, prHigh;
@property (nonatomic) BOOL spo2LowHit, spo2HighHit, prLowHit, prHighHit;
@property (nonatomic) NSInteger mutedRemaining;     // s (0 = allarmi attivi)
@property (nonatomic) float battery;                // 0..1
@property (nonatomic) BOOL charging, linked, sensorOn, searching;
@property (nonatomic) BOOL showLink;               // icona collegamento nella barra di stato (ora sta nell'intestazione dell'app)
@property (nonatomic, copy) NSString *dateText, *timeText;
@property (nonatomic) double pulseAmp;              // 0..1 barra accanto al pletismo: si riempie e si svuota con l'onda (ogni frame)
@property (nonatomic, strong) OxiMenu *menu;        // disegnato se la pagina non è "chiusa"
@property (nonatomic, copy) NSString *versionText;
- (void)refresh;                                    // ridisegna (valori cambiati)
- (NSString *)zoneAtPoint:(CGPoint)p;               // "spo2", "pr", "pleth" oppure nil (schermata principale)
@end
