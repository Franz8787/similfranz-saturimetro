#import "OxiLocalState.h"

static NSDictionary *kLimitRanges(void) {
    return @{ @"spo2_low": @[@20, @99], @"spo2_high": @[@21, @100], @"pr_low": @[@20, @240], @"pr_high": @[@25, @250] };
}
static BOOL IntValue(id v, NSInteger lo, NSInteger hi, NSInteger *out, NSString *name, NSString **err) {
    if (![v isKindOfClass:[NSNumber class]]) { if (err) *err = [NSString stringWithFormat:@"%@: number expected", name]; return NO; }
    double d = [v doubleValue];
    if (d != floor(d) || d < lo || d > hi) { if (err) *err = [NSString stringWithFormat:@"%@: integer %ld..%ld expected", name, (long)lo, (long)hi]; return NO; }
    *out = (NSInteger)d; return YES;
}
static BOOL BoolValue(id v, BOOL *out, NSString *name, NSString **err) {
    if (![v isKindOfClass:[NSNumber class]]) { if (err) *err = [NSString stringWithFormat:@"%@: boolean expected", name]; return NO; }
    *out = [v boolValue]; return YES;
}

@implementation OxiLocalState {
    // paziente: valore di partenza, obiettivo, inizio e durata della transizione (tempo di simulazione)
    double _spFrom, _spTo, _spAt, _spDur, _prFrom, _prTo, _prAt, _prDur;
    BOOL _pulsePresent, _signalValid, _lowPerf, _cpr, _running;
    NSString *_rhythm; NSInteger _motion; double _motionUntil;
    double _pausedAt, _pausedTotal;                             // pausa: il tempo di simulazione si ferma
    // saturimetro
    BOOL _power, _sensor; double _sensorAt; NSString *_site;
    NSInteger _volume, _acquire; double _mutedUntil; NSDictionary *_limits;
    NSUInteger _revision;
}

+ (NSDictionary *)defaultLimits { return @{ @"spo2_low": @85, @"spo2_high": @100, @"pr_low": @30, @"pr_high": @170 }; }
+ (NSArray *)supportedCommands {
    return @[@"set_oximeter", @"set_sensor", @"reset_scenario", @"transition", @"set_spo2", @"set_pulse_rate", @"set_pulse_present",
             @"set_spo2_signal_valid", @"set_spo2_low_perfusion", @"set_patient_motion", @"set_rhythm", @"set_cpr_active", @"set_simulation_running"];
}

- (instancetype)init {
    if ((self = [super init])) {
        _clock = ^NSTimeInterval { return [NSProcessInfo processInfo].systemUptime; };
        _deviceId = @"saturimetro-01";
        [self reset];
    }
    return self;
}
- (NSUInteger)revision { @synchronized (self) { return _revision; } }
- (BOOL)power { @synchronized (self) { return _power; } }

- (double)simNow { double t = _clock(); return (_running ? t : _pausedAt) - _pausedTotal; }
- (double)ramp:(double)from to:(double)to at:(double)at dur:(double)dur now:(double)now {
    if (dur <= 0 || now >= at + dur) return to;
    if (now <= at) return from;
    return from + (to - from) * (now - at) / dur;
}

- (void)reset {
    @synchronized (self) {
        _running = YES; _pausedAt = 0; _pausedTotal = 0;
        _spFrom = _spTo = 97; _prFrom = _prTo = 78; _spDur = _prDur = 0; _spAt = _prAt = 0;
        _pulsePresent = YES; _signalValid = YES; _lowPerf = NO; _cpr = NO; _rhythm = @"sinus"; _motion = 0; _motionUntil = 0;
        _power = NO; _sensor = NO; _sensorAt = 0; _site = nil;
        _volume = 70; _mutedUntil = 0; _limits = [OxiLocalState defaultLimits];
        _revision++;
    }
}

- (BOOL)applyCommand:(NSDictionary *)cmd error:(NSString **)error {
    NSString *name = [cmd[@"command"] isKindOfClass:[NSString class]] ? cmd[@"command"] : nil;
    id value = cmd[@"value"];
    if (!name) { if (error) *error = @"command: string expected"; return NO; }
    @synchronized (self) {
        double now = [self simNow]; BOOL b; NSInteger v;
        if ([name isEqualToString:@"set_oximeter"]) {
            if (![value isKindOfClass:[NSDictionary class]]) { if (error) *error = @"value: object expected"; return NO; }
            if (value[@"power"]) { if (!BoolValue(value[@"power"], &b, @"power", error)) return NO; _power = b; if (!b) _mutedUntil = 0; }
            if (value[@"volume"]) { if (!IntValue(value[@"volume"], 0, 100, &v, @"volume", error)) return NO; _volume = v; }
            if (value[@"acquire_s"]) { if (!IntValue(value[@"acquire_s"], 0, 60, &v, @"acquire_s", error)) return NO; _acquire = v; }   // 0 = automatico (5-10 s)
            if (value[@"mute_s"]) { if (!IntValue(value[@"mute_s"], 0, 900, &v, @"mute_s", error)) return NO; _mutedUntil = v ? _clock() + v : 0; }
            NSDictionary *lim = value[@"alarm_limits"];
            if (lim) {
                if (![lim isKindOfClass:[NSDictionary class]]) { if (error) *error = @"alarm_limits: object expected"; return NO; }
                NSMutableDictionary *next = [_limits mutableCopy]; NSDictionary *rg = kLimitRanges();
                for (NSString *k in lim) {
                    if (!rg[k]) { if (error) *error = [NSString stringWithFormat:@"alarm_limits.%@: unknown limit", k]; return NO; }
                    if (!IntValue(lim[k], [rg[k][0] integerValue], [rg[k][1] integerValue], &v, k, error)) return NO; next[k] = @(v);
                }
                if ([next[@"spo2_low"] integerValue] >= [next[@"spo2_high"] integerValue] || [next[@"pr_low"] integerValue] >= [next[@"pr_high"] integerValue]) {
                    if (error) *error = @"alarm_limits: low limit must be below high limit"; return NO;
                }
                _limits = next;
            }
        } else if ([name isEqualToString:@"set_sensor"]) {
            if (![value isKindOfClass:[NSDictionary class]] || ![value[@"sensor"] isEqualToString:@"oxi"]) { if (error) *error = @"set_sensor: only {\"sensor\":\"oxi\",\"connected\":bool} is supported"; return NO; }
            if (!BoolValue(value[@"connected"], &b, @"connected", error)) return NO;
            id site = value[@"site"];
            if (site && site != [NSNull null]) {
                NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"] invertedSet];
                if (![site isKindOfClass:[NSString class]] || [site length] == 0 || [site length] > 24 || [site rangeOfCharacterFromSet:bad].location != NSNotFound) {
                    if (error) *error = @"site: lowercase letters, digits and _ (max 24)"; return NO;
                }
            }
            if (b && !_sensor) _sensorAt = now;
            _sensor = b; _site = b ? ([site isKindOfClass:[NSString class]] ? site : (_site ?: @"finger_r2")) : nil;
        } else if ([name isEqualToString:@"reset_scenario"]) {
            [self reset]; return YES;
        } else if ([name isEqualToString:@"transition"]) {
            // {"params":{"spo2_percent":88,"pulse_rate_bpm":120},"duration_s":30}
            if (![value isKindOfClass:[NSDictionary class]] || ![value[@"params"] isKindOfClass:[NSDictionary class]]) { if (error) *error = @"transition: {params:{...}, duration_s} expected"; return NO; }
            NSInteger dur = 0; if (value[@"duration_s"] && !IntValue(value[@"duration_s"], 0, 600, &dur, @"duration_s", error)) return NO;
            NSDictionary *pr = value[@"params"]; NSInteger sp = -1, pu = -1;
            for (NSString *k in pr) {
                if ([k isEqualToString:@"spo2_percent"]) { if (!IntValue(pr[k], 1, 100, &sp, k, error)) return NO; }
                else if ([k isEqualToString:@"pulse_rate_bpm"] || [k isEqualToString:@"heart_rate_bpm"]) { if (!IntValue(pr[k], 0, 250, &pu, k, error)) return NO; }
                else { if (error) *error = [NSString stringWithFormat:@"params.%@: not supported by the oximeter", k]; return NO; }
            }
            if (sp >= 0) { _spFrom = [self ramp:_spFrom to:_spTo at:_spAt dur:_spDur now:now]; _spTo = sp; _spAt = now; _spDur = dur; }
            if (pu >= 0) { _prFrom = [self ramp:_prFrom to:_prTo at:_prAt dur:_prDur now:now]; _prTo = pu; _prAt = now; _prDur = dur; }
        } else if ([name isEqualToString:@"set_spo2"]) {
            if (!IntValue(value, 1, 100, &v, @"spo2_percent", error)) return NO; _spFrom = _spTo = v; _spDur = 0;
        } else if ([name isEqualToString:@"set_pulse_rate"]) {
            if (!IntValue(value, 0, 250, &v, @"pulse_rate_bpm", error)) return NO; _prFrom = _prTo = v; _prDur = 0;
        } else if ([name isEqualToString:@"set_pulse_present"]) {
            if (!BoolValue(value, &b, @"pulse_present", error)) return NO; _pulsePresent = b;
        } else if ([name isEqualToString:@"set_spo2_signal_valid"]) {
            if (!BoolValue(value, &b, @"spo2_signal_valid", error)) return NO; _signalValid = b;
        } else if ([name isEqualToString:@"set_spo2_low_perfusion"]) {
            if (!BoolValue(value, &b, @"spo2_low_perfusion", error)) return NO; _lowPerf = b;
        } else if ([name isEqualToString:@"set_patient_motion"]) {
            // "off" | "light" | "strong"  oppure {"motion":"light","duration_s":30}
            NSString *m = [value isKindOfClass:[NSString class]] ? value : ([value isKindOfClass:[NSDictionary class]] ? value[@"motion"] : nil);
            NSInteger lvl = [m isEqualToString:@"off"] ? 0 : [m isEqualToString:@"light"] ? 1 : [m isEqualToString:@"strong"] ? 2 : -1;
            if (lvl < 0) { if (error) *error = @"patient_motion: off | light | strong"; return NO; }
            NSInteger dur = 30;
            if ([value isKindOfClass:[NSDictionary class]] && value[@"duration_s"] && !IntValue(value[@"duration_s"], 0, 600, &dur, @"duration_s", error)) return NO;
            _motion = lvl; _motionUntil = (lvl && dur) ? now + dur : 0;
        } else if ([name isEqualToString:@"set_rhythm"]) {
            if (![value isKindOfClass:[NSString class]] || !([value isEqualToString:@"sinus"] || [value isEqualToString:@"afib"])) { if (error) *error = @"rhythm: sinus | afib"; return NO; }
            _rhythm = value;
        } else if ([name isEqualToString:@"set_cpr_active"]) {
            if (!BoolValue(value, &b, @"cpr_active", error)) return NO; _cpr = b;
        } else if ([name isEqualToString:@"set_simulation_running"]) {
            if (!BoolValue(value, &b, @"simulation_running", error)) return NO;
            if (b && !_running) { _pausedTotal += _clock() - _pausedAt; _running = YES; }
            else if (!b && _running) { _pausedAt = _clock(); _running = NO; }
        } else { if (error) *error = [NSString stringWithFormat:@"unknown command '%@'", name]; return NO; }
        _revision++;
    }
    return YES;
}

- (NSDictionary *)stateDictionary {
    @synchronized (self) {
        double now = [self simNow], real = _clock();
        if (_motion && _motionUntil && now >= _motionUntil) { _motion = 0; _motionUntil = 0; }
        NSInteger sp = (NSInteger)lround([self ramp:_spFrom to:_spTo at:_spAt dur:_spDur now:now]);
        NSInteger pr = (NSInteger)lround([self ramp:_prFrom to:_prTo at:_prAt dur:_prDur now:now]);
        NSNull *null = [NSNull null];
        NSInteger spRem = (_spDur > 0 && now < _spAt + _spDur) ? (NSInteger)ceil(_spAt + _spDur - now) : 0;
        NSInteger prRem = (_prDur > 0 && now < _prAt + _prDur) ? (NSInteger)ceil(_prAt + _prDur - now) : 0;
        return @{
            @"device_id": _deviceId, @"device_type": @"oximeter", @"revision": @(_revision),
            @"spo2_percent": @(sp), @"pulse_rate_bpm": @(pr), @"heart_rate_bpm": @(pr),
            @"systolic_mmhg": @(_lowPerf ? 80 : 120),
            @"pulse_present": @(_pulsePresent), @"spo2_signal_valid": @(_signalValid),
            @"spo2_low_perfusion": @(_lowPerf), @"spo2_low_perfusion_flag": @(_lowPerf),
            @"cpr_active": @(_cpr), @"simulation_running": @(_running), @"rhythm": _rhythm, @"spo2_delay_s": @0,
            @"patient_motion": @[@"off", @"light", @"strong"][(NSUInteger)_motion],
            @"patient_motion_remaining_s": @((_motion && _motionUntil) ? (NSInteger)ceil(_motionUntil - now) : 0),
            @"targets": @{ @"spo2_percent": @((NSInteger)_spTo), @"pulse_rate_bpm": @((NSInteger)_prTo), @"remaining_s": @(MAX(spRem, prRem)) },
            @"sensors": @{ @"oxi": @(_sensor) },
            @"oximeter": @{ @"power": @(_power), @"online": @YES, @"sensor_connected": @(_sensor),
                            @"sensor_since_s": _sensor ? @(floor(now - _sensorAt)) : null, @"site": _site ?: null,
                            @"cuff_occluded": @NO, @"alarm_limits": _limits, @"volume": @(_volume), @"acquire_s": @(_acquire),
                            @"muted_remaining_s": @(_mutedUntil > real ? (NSInteger)ceil(_mutedUntil - real) : 0) },
        };
    }
}
@end
