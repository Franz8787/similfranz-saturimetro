#import "OxiSound.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <pthread.h>
#include <math.h>
#import "SFLog.h"

#define SR 22050.0
#define FRAMES 384
#define NBUF 3
#define MAXVOICE 8

typedef struct { int kind; double freq, phase, amp; long pos, len; double attack, release; } Voice;

@implementation OxiSound {
    AudioQueueRef _queue; AudioQueueBufferRef _bufs[NBUF];
    pthread_mutex_t _lock; Voice _voices[MAXVOICE];
    OxiAlarmLevel _alarm; long _alarmPos; double _alarmGain, _pulseGain;
}
static void OxiCallback(void *user, AudioQueueRef q, AudioQueueBufferRef buf);

- (instancetype)init { if ((self = [super init])) { pthread_mutex_init(&_lock, NULL); _alarmGain = 0.7; _pulseGain = 0.5; } return self; }
- (void)dealloc { [self stop]; pthread_mutex_destroy(&_lock); }

- (BOOL)start {
    if (_running) return YES;
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if (![session setCategory:AVAudioSessionCategoryPlayback error:&err]) SFLog(@"audio: setCategory %@", err);   // suona anche con l'interruttore laterale in silenzioso
    if (![session setActive:YES error:&err]) SFLog(@"audio: setActive %@", err);
    AudioStreamBasicDescription f = {0};
    f.mSampleRate = SR; f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    f.mBytesPerPacket = 2; f.mFramesPerPacket = 1; f.mBytesPerFrame = 2; f.mChannelsPerFrame = 1; f.mBitsPerChannel = 16;
    OSStatus st = AudioQueueNewOutput(&f, OxiCallback, (__bridge void *)self, NULL, NULL, 0, &_queue);
    if (st != noErr) { SFLog(@"audio: AudioQueueNewOutput %d", (int)st); return NO; }
    for (int i = 0; i < NBUF; i++) { AudioQueueAllocateBuffer(_queue, FRAMES * 2, &_bufs[i]); OxiCallback((__bridge void *)self, _queue, _bufs[i]); }
    AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, 1.0);
    st = AudioQueueStart(_queue, NULL);
    if (st != noErr) { SFLog(@"audio: AudioQueueStart %d", (int)st); return NO; }
    _running = YES; SFLog(@"audio: AudioQueue avviata");
    return YES;
}
- (void)stop { if (!_running) return; AudioQueueStop(_queue, true); AudioQueueDispose(_queue, true); _queue = NULL; _running = NO; }

- (void)setPulseGain:(double)g { pthread_mutex_lock(&_lock); _pulseGain = MAX(0, MIN(1, g)); pthread_mutex_unlock(&_lock); }
- (double)pulseGain { return _pulseGain; }
- (void)setAlarmGain:(double)g { pthread_mutex_lock(&_lock); _alarmGain = MAX(0, MIN(1, g)); pthread_mutex_unlock(&_lock); }
- (double)alarmGain { return _alarmGain; }

- (void)addVoice:(Voice)v {
    pthread_mutex_lock(&_lock);
    for (int i = 0; i < MAXVOICE; i++) if (_voices[i].kind == 0) { _voices[i] = v; break; }
    pthread_mutex_unlock(&_lock);
}
- (void)beep:(double)hz {
    if (_pulseGain <= 0.001) return;
    Voice v = {0}; v.kind = 1; v.freq = hz; v.amp = 0.42 * _pulseGain; v.len = (long)(0.07 * SR); v.attack = 0.003 * SR; v.release = 0.025 * SR;
    [self addVoice:v];
}
- (void)keyClick {
    Voice v = {0}; v.kind = 1; v.freq = 1800; v.amp = 0.18; v.len = (long)(0.025 * SR); v.attack = 0.001 * SR; v.release = 0.012 * SR;
    [self addVoice:v];
}
- (void)powerChime {
    double f[3] = {660, 880, 1100};
    for (int i = 0; i < 3; i++) {
        Voice v = {0}; v.kind = 1; v.freq = f[i]; v.amp = 0.35; v.len = (long)(0.12 * SR); v.attack = 0.005 * SR; v.release = 0.05 * SR; v.pos = -(long)(i * 0.13 * SR);
        [self addVoice:v];
    }
}
- (void)setAlarm:(OxiAlarmLevel)level {
    pthread_mutex_lock(&_lock);
    if (level != _alarm) { _alarm = level; _alarmPos = 0; }
    pthread_mutex_unlock(&_lock);
}

typedef struct { double t, d, f; } Pulse;
static const Pulse kHigh[] = { {0,.12,960},{.20,.12,960},{.40,.12,960},{.85,.12,960},{1.05,.12,960} };   // 3+2 ogni 6 s
static const Pulse kMed[]  = { {0,.20,660},{.32,.20,660},{.64,.20,660} };                               // 3 ogni 8 s
static const Pulse kLow[]  = { {0,.22,520},{.40,.22,520} };                                             // 2 ogni 10 s (promemoria: sensore scollegato, ricerca polso…)
static double alarmSample(OxiAlarmLevel a, long pos) {
    const Pulse *p; int n; double period;
    switch (a) {
        case OxiAlarmHigh:   p = kHigh; n = 5; period = 6.0; break;
        case OxiAlarmMedium: p = kMed;  n = 3; period = 8.0; break;
        case OxiAlarmLow:    p = kLow;  n = 2; period = 10.0; break;
        default: return 0;
    }
    double t = fmod(pos / SR, period);
    for (int i = 0; i < n; i++) {
        double x = t - p[i].t;
        if (x >= 0 && x < p[i].d) {
            double env = MIN(1.0, MIN(x, p[i].d - x) / 0.012), w = 2 * M_PI * p[i].f * x;
            return env * 0.42 * (sin(w) + 0.35 * sin(3 * w) + 0.15 * sin(5 * w)) / 1.5;
        }
    }
    return 0;
}

- (void)render:(int16_t *)out frames:(UInt32)n {
    pthread_mutex_lock(&_lock);
    for (UInt32 i = 0; i < n; i++) {
        double s = 0;
        for (int k = 0; k < MAXVOICE; k++) {
            Voice *v = &_voices[k];
            if (v->kind == 0) continue;
            if (v->pos < 0) { v->pos++; continue; }          // partenza ritardata (accordo di accensione)
            double env = 1.0;
            if (v->pos < v->attack) env = v->pos / v->attack;
            long left = v->len - v->pos;
            if (left < v->release) env *= MAX(0.0, left / v->release);
            s += v->amp * env * sin(v->phase);
            v->phase += 2 * M_PI * v->freq / SR;
            if (++v->pos >= v->len) v->kind = 0;
        }
        if (_alarm != OxiAlarmNone) { s += _alarmGain * alarmSample(_alarm, _alarmPos); _alarmPos++; }
        if (s > 1) s = 1; if (s < -1) s = -1;
        out[i] = (int16_t)(s * 30000);
    }
    pthread_mutex_unlock(&_lock);
}
static void OxiCallback(void *user, AudioQueueRef q, AudioQueueBufferRef buf) {
    OxiSound *e = (__bridge OxiSound *)user;
    [e render:(int16_t *)buf->mAudioData frames:FRAMES];
    buf->mAudioDataByteSize = FRAMES * 2;
    AudioQueueEnqueueBuffer(q, buf, 0, NULL);
}
@end
