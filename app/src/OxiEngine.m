#import "OxiEngine.h"
#include <math.h>

#define MAXB 64
#define LOOKAHEAD 1.5

typedef struct { NSTimeInterval t; double rr, prevRR; BOOL perfused; } Beat;   // rr = intervallo dopo, prevRR = riempimento prima

static inline double gauss(double x, double mu, double sigma) { double z = (x - mu) / sigma; return exp(-0.5 * z * z); }

// forma dell'onda di polso al dito (0..~1): salita rapida, decadimento, onda dicrota
static double plethPulse(double tau) {
    if (tau < 0) return 0;
    double up = 0.13;
    if (tau < up) return 0.5 * (1 - cos(M_PI * tau / up));
    double d = tau - up;
    return exp(-d / 0.30) * 0.85 + 0.15 * exp(-d / 0.9) + 0.12 * gauss(tau, 0.36, 0.035) * exp(-d / 0.5);
}
// onda compressa nell'intervallo RR: torna alla linea di base prima del battito successivo
static double fitToRR(double tau, double rr) {
    double k = MIN(1.0, rr / 0.9);
    double t1 = tau / k, end = rr / k;
    if (tau >= rr) return 0;
    return MAX(0.0, plethPulse(t1) - plethPulse(end) * (tau / rr));
}
static double cprPulse(double ph) { return ph < 0.12 ? 0.5 * (1 - cos(M_PI * ph / 0.12)) : exp(-(ph - 0.12) / 0.16); }
static double motionArtifact(NSTimeInterval t, NSInteger level) {
    double a = level == 2 ? 1.0 : 0.45;
    return a * (0.6 * sin(2 * M_PI * 1.7 * t) * sin(2 * M_PI * 0.23 * t) + 0.4 * sin(2 * M_PI * 3.1 * t + 1.3) * sin(2 * M_PI * 0.41 * t));
}

@implementation OxiEngine {
    Beat _beats[MAXB]; int _count, _head;
    NSTimeInterval _next, _lastT; BOOL _started;
    unsigned int _rng;
    double _hr, _perfusion; BOOL _pulse, _cpr, _valid, _searching, _on; NSInteger _motion; NSString *_rhythm;
    double _amp, _lastRR; int _runSign, _runLen;
}
- (instancetype)initWithSeed:(unsigned int)seed { if ((self = [super init])) { _rng = seed ?: 7; _perfusion = 1; } return self; }
- (double)rand01 { _rng = _rng * 1664525u + 1013904223u; return (_rng >> 8) / 16777216.0; }

- (void)updateWithPatient:(OxiPatient *)p signal:(OxiSignal)sig {
    _hr = p.pulseRate > 0 ? p.pulseRate : p.heartRate;
    _pulse = p.pulsePresent; _cpr = p.cpr; _motion = p.motion; _rhythm = p.rhythm ?: @"sinus";
    _valid = p.signalValid && !p.cuffOccluded;
    _on = p.sensorConnected; _searching = (sig == OxiSignalSearching);
    _perfusion = MAX(0.12, MIN(1.0, (p.systolic - 40.0) / 60.0));
    if (p.lowPerfFlag) _perfusion = MIN(_perfusion, 0.35);
    if (!p.running) _pulse = NO;
}

- (void)addBeat:(Beat)b {
    int idx = (_head + _count) % MAXB;
    if (_count == MAXB) { _head = (_head + 1) % MAXB; _count--; idx = (_head + _count) % MAXB; }
    _beats[idx] = b; _count++;
}
- (double)nextRR {
    double rr = 60.0 / MAX(_hr, 1.0);
    if ([_rhythm isEqualToString:@"afib"]) {
        // FA: irregolarmente irregolare. Intervalli a campana (~17 %), senza estremi e senza serie:
        // al massimo 3 battiti di fila nella stessa direzione, poi si inverte (niente run di accelerazione/rallentamento)
        double g = ([self rand01] + [self rand01] + [self rand01] - 1.5) * 2.0;           // ~normale, |g| <= 3
        double f = MAX(0.62, MIN(1.45, 1.0 + 0.16 * g));                                   // rapporto con l'intervallo medio
        int sign = f > 1.04 ? 1 : (f < 0.96 ? -1 : 0);
        if (sign && sign == _runSign && (_runLen >= 3 || (_runLen == 2 && [self rand01] < 0.6))) { f = MAX(0.62, MIN(1.45, 2.0 - f)); sign = -sign; }
        if (sign && sign == _runSign) _runLen++; else { _runSign = sign; _runLen = 1; }
        rr *= f;
    }
    else if ([_rhythm hasPrefix:@"vt"]) rr *= 0.99 + 0.02 * [self rand01];
    else rr *= 0.97 + 0.06 * [self rand01];                                              // variabilità sinusale
    return MAX(0.2, rr);
}
- (void)scheduleUntil:(NSTimeInterval)t {
    if (!_started) { _next = t; _started = YES; }
    if (_next < t - 2) _next = t;                                                        // dopo una pausa lunga riparte
    while (_next <= t + LOOKAHEAD) {
        if (_pulse && _hr >= 1) {
            double rr = [self nextRR], prev = _lastRR > 0 ? _lastRR : 60.0 / MAX(_hr, 1.0);
            Beat b = { _next, rr, prev, YES }; [self addBeat:b]; _next += rr; _lastRR = rr;
        }
        else _next += 0.25;
    }
}
- (BOOL)pulseAt:(NSTimeInterval)t delay:(double)delay tau:(double *)tau rr:(double *)rrNext amp:(double *)amp {
    int found = -1;
    for (int i = 0; i < _count; i++) { Beat *b = &_beats[(_head + i) % MAXB]; if (b->t + delay <= t) found = i; else break; }
    if (found < 0) return NO;
    Beat *b = &_beats[(_head + found) % MAXB];
    if (!b->perfused) return NO;
    double next = (found + 1 < _count) ? _beats[(_head + found + 1) % MAXB].t : MAX(_next, b->t + b->rr);
    *tau = t - (b->t + delay); *rrNext = MAX(0.2, next - b->t);
    double meanRR = 60.0 / MAX(_hr, 1.0);
    double fill = b->prevRR / meanRR;                                                  // riempimento: onda piena dopo una pausa normale o lunga,
    *amp = fill >= 0.95 ? 1.0 : MAX(0.35, 0.35 + 0.65 * (fill - 0.6) / 0.35);          // sempre più piccola dopo un intervallo corto
    return YES;
}
- (double)plethAt:(NSTimeInterval)t {
    [self scheduleUntil:t];
    _lastT = t;
    if (!_on || _searching) { _amp = 0; return 0; }
    if (!_valid) { _amp = 0.3; return 0.35 + 0.25 * sin(2 * M_PI * 1.3 * t) * sin(2 * M_PI * 0.37 * t) + 0.15 * ([self rand01] - 0.5); }
    if (!_pulse) {
        if (_cpr) { _amp = 0.2; return 0.18 * cprPulse(fmod(t * 110.0 / 60.0 + 0.85, 1.0)); }
        _amp = 0; return 0;
    }
    double tau, rr, amp;
    if (![self pulseAt:t delay:0.22 tau:&tau rr:&rr amp:&amp]) { _amp = 0; return 0; }
    double v = amp * fitToRR(tau, rr) * _perfusion;
    _amp = _perfusion * amp;
    if (_perfusion < 0.55) {
        double bad = (0.55 - _perfusion) / 0.43;
        v *= 0.65 + 0.35 * sin(2 * M_PI * 0.37 * t + 1.1 * sin(2 * M_PI * 0.11 * t));
        v += bad * (0.05 * sin(2 * M_PI * 0.45 * t) + 0.03 * sin(2 * M_PI * 3.3 * t) * sin(2 * M_PI * 0.7 * t) + 0.035 * ([self rand01] - 0.5));
    }
    if (_motion) v = v * (_motion == 2 ? 0.5 : 0.8) + 0.45 * motionArtifact(t * 0.8 + 3.1, _motion) + (_motion == 2 ? 0.35 : 0.1);
    return MAX(0, MIN(1.1, v * 0.8));
}
- (NSTimeInterval)lastPerfusedBeatAtOrBefore:(NSTimeInterval)t {
    [self scheduleUntil:t];
    NSTimeInterval last = -1;
    for (int i = 0; i < _count; i++) { Beat *b = &_beats[(_head + i) % MAXB]; if (b->perfused && b->t <= t) last = b->t; }
    return last;
}
- (double)amplitude { return _amp; }
@end
