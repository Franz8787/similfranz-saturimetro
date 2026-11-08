// SimulaFranz_Saturimetro — audio sintetizzato in tempo reale (AudioQueue, iOS 2+): nessun file audio.
//  - tono del polso a ogni battito, altezza legata alla SpO2
//  - allarmi a priorità alta / media / bassa con cadenze distinte (ispirate a IEC 60601-1-8)
//  - clic dei tasti, suono di accensione
#import <Foundation/Foundation.h>
#import "OxiState.h"

@interface OxiSound : NSObject
@property (nonatomic, readonly) BOOL running;
- (BOOL)start;
- (void)stop;
@property (nonatomic) double pulseGain;      // 0..1 (volume del tono del polso, menu del dispositivo)
@property (nonatomic) double alarmGain;      // 0..1 (volume allarmi, condiviso con il controller)
- (void)beep:(double)hz;                     // tono del polso
- (void)setAlarm:(OxiAlarmLevel)level;       // cadenza continua finché non viene cambiata
- (void)keyClick;
- (void)powerChime;
@end
