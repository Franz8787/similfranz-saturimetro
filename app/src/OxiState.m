#import "OxiState.h"
#include <math.h>

static NSInteger I(id v, NSInteger def) { return [v isKindOfClass:[NSNumber class]] ? [v integerValue] : def; }
static BOOL B(id v, BOOL def) { return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : def; }

@implementation OxiPatient
+ (instancetype)patientFromState:(NSDictionary *)s {
    if (![s isKindOfClass:[NSDictionary class]] || !s[@"spo2_percent"]) return nil;
    OxiPatient *p = [OxiPatient new];
    p.spo2 = I(s[@"spo2_percent"], 0);
    p.pulseRate = I(s[@"pulse_rate_bpm"], I(s[@"heart_rate_bpm"], 0));
    p.heartRate = I(s[@"heart_rate_bpm"], 0);
    p.systolic = I(s[@"systolic_mmhg"], 120);
    p.pulsePresent = B(s[@"pulse_present"], YES);
    p.signalValid = B(s[@"spo2_signal_valid"], YES);
    p.lowPerfusion = B(s[@"spo2_low_perfusion"], NO);
    p.lowPerfFlag = B(s[@"spo2_low_perfusion_flag"], NO);
    p.cpr = B(s[@"cpr_active"], NO);
    p.running = B(s[@"simulation_running"], YES);
    NSString *m = [s[@"patient_motion"] isKindOfClass:[NSString class]] ? s[@"patient_motion"] : @"off";
    p.motion = [m isEqualToString:@"strong"] ? 2 : ([m isEqualToString:@"light"] ? 1 : 0);
    p.rhythm = [s[@"rhythm"] isKindOfClass:[NSString class]] ? s[@"rhythm"] : @"sinus";
    p.delaySec = I(s[@"spo2_delay_s"], 0);
    p.revision = (NSUInteger)I(s[@"revision"], 0);
    NSDictionary *o = [s[@"oximeter"] isKindOfClass:[NSDictionary class]] ? s[@"oximeter"] : @{};
    p.sensorConnected = B(o[@"sensor_connected"], NO);
    p.cuffOccluded = B(o[@"cuff_occluded"], NO);
    p.remotePower = B(o[@"power"], NO);
    p.sensorSince = p.sensorConnected ? (double)I(o[@"sensor_since_s"], 0) : -1;
    p.volume = I(o[@"volume"], 70);
    p.acquireSec = MAX(0, I(o[@"acquire_s"], 0));
    p.mutedRemaining = I(o[@"muted_remaining_s"], 0);
    NSDictionary *lim = [o[@"alarm_limits"] isKindOfClass:[NSDictionary class]] ? o[@"alarm_limits"] : nil;
    p.limits = lim.count ? lim : @{ @"spo2_low": @85, @"spo2_high": @100, @"pr_low": @30, @"pr_high": @170 };
    return p;
}
- (NSInteger)limit:(NSString *)key { return I(self.limits[key], 0); }
@end

OxiSignal OxiSignalFor(OxiPatient *p) {
    if (!p || !p.sensorConnected) return OxiSignalSensorOff;
    double d = p.delaySec;
    if (d > 0 && p.sensorSince < d / 2.0) return OxiSignalSearching;
    if (!p.signalValid || p.cuffOccluded) return OxiSignalInterference;
    if (!p.pulsePresent) return OxiSignalNoPulse;
    // polso troppo debole o lento (es. subito dopo il ROSC, mentre i valori risalgono da 0): un saturimetro vero
    // non mostra un polso di 1 né una SpO2 di 3%, resta in ricerca finché il segnale non è plausibile
    if (p.pulseRate < 25 || p.spo2 < 50) return OxiSignalNoPulse;
    if (d > 0 && p.sensorSince < d) return OxiSignalAcquiring;
    return OxiSignalOK;
}

@implementation OxiAlarmResult
@end

OxiAlarmResult *OxiEvaluate(OxiPatient *p, OxiSignal sig, NSTimeInterval noPulseFor, NSTimeInterval searchFor) {
    OxiAlarmResult *r = [OxiAlarmResult new];
    NSMutableArray *high = [NSMutableArray array], *med = [NSMutableArray array], *low = [NSMutableArray array];
    if (!p) { r.messages = @[@"NESSUN COLLEGAMENTO"]; r.level = OxiAlarmNone; return r; }
    if (p.running) {
        switch (sig) {
            case OxiSignalSensorOff: [low addObject:@"SENSORE SCOLLEGATO"]; break;
            case OxiSignalSearching:
                [low addObject:searchFor > 30 ? @"POLSO NON TROVATO" : @"RICERCA POLSO"]; break;
            case OxiSignalInterference: [low addObject:@"INTERFERENZA"]; break;
            case OxiSignalNoPulse:
                if (noPulseFor >= 10) { [high addObject:@"POLSO PERSO"]; r.prLevel = OxiAlarmHigh; }
                else [low addObject:@"RICERCA POLSO"];
                break;
            case OxiSignalAcquiring: break;
            case OxiSignalOK: {
                NSInteger lo = [p limit:@"spo2_low"], hi = [p limit:@"spo2_high"];
                if (p.spo2 < lo) {
                    BOOL crit = p.spo2 < lo - 5;
                    [(crit ? high : med) addObject:[NSString stringWithFormat:@"SpO2 BASSA < %ld", (long)lo]];
                    r.spo2Level = crit ? OxiAlarmHigh : OxiAlarmMedium; r.spo2LowViolated = YES;
                } else if (p.spo2 > hi) {
                    [med addObject:[NSString stringWithFormat:@"SpO2 ALTA > %ld", (long)hi]];
                    r.spo2Level = OxiAlarmMedium; r.spo2HighViolated = YES;
                }
                NSInteger plo = [p limit:@"pr_low"], phi = [p limit:@"pr_high"];
                if (p.pulseRate < plo) {
                    BOOL crit = p.pulseRate < plo - 10;
                    [(crit ? high : med) addObject:[NSString stringWithFormat:@"POLSO BASSO < %ld", (long)plo]];
                    r.prLevel = crit ? OxiAlarmHigh : OxiAlarmMedium; r.prLowViolated = YES;
                } else if (p.pulseRate > phi) {
                    BOOL crit = p.pulseRate > phi + 30;
                    [(crit ? high : med) addObject:[NSString stringWithFormat:@"POLSO ALTO > %ld", (long)phi]];
                    r.prLevel = crit ? OxiAlarmHigh : OxiAlarmMedium; r.prHighViolated = YES;
                }
                if (p.lowPerfusion || p.lowPerfFlag) [low addObject:@"BASSA PERFUSIONE"];
                if (p.motion) [low addObject:@"MOVIMENTO"];
                break;
            }
        }
    }
    NSMutableArray *all = [NSMutableArray arrayWithArray:high];
    [all addObjectsFromArray:med]; [all addObjectsFromArray:low];
    r.messages = all;
    r.level = high.count ? OxiAlarmHigh : med.count ? OxiAlarmMedium : low.count ? OxiAlarmLow : OxiAlarmNone;
    return r;
}

double OxiBeepFrequency(NSInteger spo2) {
    // ~1/3 di semitono per punto di SpO2: 100% = 880 Hz, 90% ≈ 698 Hz, 80% ≈ 554 Hz (come il monitor)
    double s = MAX(50, MIN(100, spo2));
    return 880.0 * pow(2.0, (s - 100.0) / 30.0);
}

#pragma mark - Menu

@implementation OxiMenu {
    NSInteger _editStep;
}
+ (NSArray *)mainItems { return @[@"Limiti allarme", @"Volume polso", @"Volume allarmi", @"Collegamento", @"Informazioni", @"Azzera scenario e spegni", @"Esci"]; }
+ (NSArray *)connectItems { return @[@"Abbinamento diretto (QR)", @"Ecosistema monitor", @"Indietro"]; }
+ (NSArray *)limitKeys { return @[@"spo2_high", @"spo2_low", @"pr_high", @"pr_low"]; }
+ (NSString *)limitTitle:(NSString *)key {
    NSDictionary *t = @{ @"spo2_high": @"SpO2 alto", @"spo2_low": @"SpO2 basso", @"pr_high": @"Polso alto", @"pr_low": @"Polso basso" };
    return t[key] ?: key;
}
- (instancetype)init {
    if ((self = [super init])) { _limits = @{ @"spo2_low": @85, @"spo2_high": @100, @"pr_low": @30, @"pr_high": @170 }; _pulseVolume = 5; _alarmVolume = 7; }
    return self;
}
- (void)open { _page = OxiMenuMain; _cursor = 0; _editing = NO; }
- (void)openLimitsAt:(NSInteger)cursor { _page = OxiMenuLimits; _cursor = MAX(0, MIN((NSInteger)[OxiMenu limitKeys].count, cursor)); _editing = NO; }
- (void)close { _page = OxiMenuClosed; _editing = NO; }

static NSInteger clampLimit(NSString *key, NSInteger v, NSDictionary *lim) {
    NSDictionary *rg = @{ @"spo2_low": @[@20, @99], @"spo2_high": @[@21, @100], @"pr_low": @[@20, @240], @"pr_high": @[@25, @250] };
    NSInteger lo = [rg[key][0] integerValue], hi = [rg[key][1] integerValue];
    // il limite basso resta sotto quello alto (e viceversa)
    if ([key isEqualToString:@"spo2_low"]) hi = MIN(hi, [lim[@"spo2_high"] integerValue] - 1);
    if ([key isEqualToString:@"spo2_high"]) lo = MAX(lo, [lim[@"spo2_low"] integerValue] + 1);
    if ([key isEqualToString:@"pr_low"]) hi = MIN(hi, [lim[@"pr_high"] integerValue] - 1);
    if ([key isEqualToString:@"pr_high"]) lo = MAX(lo, [lim[@"pr_low"] integerValue] + 1);
    return MAX(lo, MIN(hi, v));
}

- (OxiMenuAction)key:(NSString *)key {
    BOOL up = [key isEqualToString:@"up"], down = [key isEqualToString:@"down"], ok = [key isEqualToString:@"ok"], back = [key isEqualToString:@"back"];
    switch (_page) {
        case OxiMenuClosed: return OxiMenuNoAction;
        case OxiMenuMain: {
            NSInteger n = (NSInteger)[OxiMenu mainItems].count;
            if (up) _cursor = (_cursor + n - 1) % n;
            else if (down) _cursor = (_cursor + 1) % n;
            else if (back) [self close];
            else if (ok) {
                switch (_cursor) {
                    case 0: _page = OxiMenuLimits; _cursor = 0; _editing = NO; break;
                    case 1: _page = OxiMenuPulseVol; break;
                    case 2: _page = OxiMenuAlarmVol; break;
                    case 3: _page = OxiMenuConnect; _cursor = 0; break;
                    case 4: _page = OxiMenuInfo; break;
                    case 5: _page = OxiMenuConfirmReset; break;
                    default: [self close]; break;
                }
            }
            return OxiMenuNoAction;
        }
        case OxiMenuLimits: {
            NSArray *keys = [OxiMenu limitKeys];
            if (_editing) {
                NSString *k = keys[(NSUInteger)_cursor];
                NSInteger step = [k hasPrefix:@"pr"] ? 5 : 1;
                NSMutableDictionary *d = [_limits mutableCopy];
                if (up) d[k] = @(clampLimit(k, [d[k] integerValue] + step, d));
                else if (down) d[k] = @(clampLimit(k, [d[k] integerValue] - step, d));
                else if (ok) { _editing = NO; return OxiMenuLimitsChanged; }
                else if (back) { _editing = NO; return OxiMenuNoAction; }     // modifica annullata: il valore resta quello mostrato
                _limits = d;
                return OxiMenuNoAction;
            }
            NSInteger n = (NSInteger)keys.count + 1;                          // + "Indietro"
            if (up) _cursor = (_cursor + n - 1) % n;
            else if (down) _cursor = (_cursor + 1) % n;
            else if (back) { _page = OxiMenuMain; _cursor = 0; }
            else if (ok) { if (_cursor == n - 1) { _page = OxiMenuMain; _cursor = 0; } else _editing = YES; }
            return OxiMenuNoAction;
        }
        case OxiMenuPulseVol:
            if (up) { _pulseVolume = MIN(10, _pulseVolume + 1); return OxiMenuPulseVolChanged; }
            if (down) { _pulseVolume = MAX(0, _pulseVolume - 1); return OxiMenuPulseVolChanged; }
            if (ok || back) { _page = OxiMenuMain; _cursor = 1; }
            return OxiMenuNoAction;
        case OxiMenuAlarmVol:
            if (up) { _alarmVolume = MIN(10, _alarmVolume + 1); return OxiMenuAlarmVolChanged; }
            if (down) { _alarmVolume = MAX(1, _alarmVolume - 1); return OxiMenuAlarmVolChanged; }   // gli allarmi non si azzerano del tutto
            if (ok || back) { _page = OxiMenuMain; _cursor = 2; }
            return OxiMenuNoAction;
        case OxiMenuInfo:
            if (ok || back) { _page = OxiMenuMain; _cursor = 4; }
            return OxiMenuNoAction;
        case OxiMenuConnect: {
            NSInteger n = (NSInteger)[OxiMenu connectItems].count;
            if (up) _cursor = (_cursor + n - 1) % n;
            else if (down) _cursor = (_cursor + 1) % n;
            else if (back || (ok && _cursor == n - 1)) { _page = OxiMenuMain; _cursor = 3; }
            else if (ok) _page = _cursor == 0 ? OxiMenuPair : OxiMenuEco;
            return OxiMenuNoAction;
        }
        case OxiMenuPair:
            if (ok || back) { _page = OxiMenuConnect; _cursor = 0; }
            return OxiMenuNoAction;
        case OxiMenuEco:
            if (ok || back) { _page = OxiMenuConnect; _cursor = 1; }
            return OxiMenuNoAction;
        case OxiMenuConfirmReset:                                 // come il monitor: conferma esplicita, ↩ annulla
            if (ok) { [self close]; return OxiMenuResetScenario; }
            if (back) { _page = OxiMenuMain; _cursor = 5; }
            return OxiMenuNoAction;
    }
    return OxiMenuNoAction;
}
@end
