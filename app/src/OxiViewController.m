// SimulaFranz_Saturimetro — controller: schermo + tastiera + audio + client del monitor.
#import "OxiViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "OxiScreenView.h"
#import "OxiKeypad.h"
#import "TraceView.h"
#import "OxiState.h"
#import "OxiEngine.h"
#import "OxiSound.h"
#import "OxiClient.h"
#import "OxiServer.h"
#import "OxiLocalState.h"
#import "NetworkInfo.h"
#import "OxiBatteryView.h"
#import "SFLog.h"

static NSString *const kPulseVolKey = @"sf_pulse_vol";

@implementation OxiViewController {
    UILabel *_title, *_footer; OxiBatteryView *_battery; OxiWifiView *_wifi; OxiScreenView *_screen; OxiKeypad *_keys;
    OxiEngine *_engine; OxiSound *_sound; OxiClient *_client; OxiMenu *_menu;
    OxiServer *_server; BOOL _local; NSString *_mode; NSTimeInterval _started, _lastLocalPoll, _pairOpenedAt; OxiMenuPage _lastPage;   // uso autonomo (server interno)
    OxiPatient *_patient; NSTimeInterval _patientAt;
    CADisplayLink *_link;
    BOOL _powered; NSTimeInterval _bootStart;                 // avvio: schermata per 2,5 s
    NSTimeInterval _powerDownAt; BOOL _powerHeld; NSTimer *_powerTimer;
    NSTimeInterval _powerGuardUntil, _muteGuardUntil, _limitsGuardUntil, _volGuardUntil;
    NSInteger _localMute;                                     // valore locale del silenziamento (s) finché il server non lo conferma
    NSTimeInterval _lastBeep, _lastJitter, _lastClock, _lastEval, _noPulseSince, _searchSince, _lowPerfSince, _msgRotateAt;
    double _jSp, _jPr; NSInteger _msgIndex; BOOL _flashOn;
    OxiAlarmResult *_alarm; OxiSignal _sig, _baseSig; NSTimeInterval _acqStart; double _acqDelay;
    NSDateFormatter *_dateF, *_timeF;
    NSArray *_stSteps; NSUInteger _stIndex;                 // autotest
    BOOL _firstState;
}

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    CGRect b = self.view.bounds;      // 320 x 480 (iPod touch 4, retina 2x)
    // intestazione: stesso colore della scocca dei tasti, testo nel blu dei tasti, batteria reale dell'iPod a destra
    UIColor *keyBlue = [UIColor colorWithRed:66 / 255.0 green:128 / 255.0 blue:196 / 255.0 alpha:1];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, b.size.width, 25)];   // ~1 mm piu' alta: niente di schiacciato
    header.backgroundColor = [UIColor colorWithRed:0.96 green:0.96 blue:0.95 alpha:1];
    [self.view addSubview:header];
    _title = [[UILabel alloc] initWithFrame:CGRectMake(8, 4, b.size.width - 90, 17)];
    _title.backgroundColor = [UIColor clearColor]; _title.textColor = keyBlue;
    _title.font = [UIFont boldSystemFontOfSize:12]; _title.textAlignment = NSTextAlignmentLeft;
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    _title.text = [NSString stringWithFormat:@"similFranzSat %@", ver];
    [header addSubview:_title];
    _battery = [[OxiBatteryView alloc] initWithFrame:CGRectMake(b.size.width - 50, 5, 44, 15)];
    _battery.tint = keyBlue;
    [header addSubview:_battery];
    _wifi = [[OxiWifiView alloc] initWithFrame:CGRectMake(b.size.width - 50 - 25, 4, 19, 16)];   // simbolo Wi-Fi accanto alla batteria
    _wifi.tint = keyBlue;
    [header addSubview:_wifi];

    // cornice scura attorno allo schermo (display incassato nella scocca, come sui saturimetri palmari)
    CGFloat kpH = 186, scrTop = 25;
    UIView *bezel = [[UIView alloc] initWithFrame:CGRectMake(0, scrTop - 2, b.size.width, b.size.height - kpH - scrTop + 2)];
    bezel.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    [self.view addSubview:bezel];
    _screen = [[OxiScreenView alloc] initWithFrame:CGRectMake(8, scrTop + 6, b.size.width - 16, bezel.frame.size.height - 14)];
    _screen.layer.cornerRadius = 3; _screen.versionText = [NSString stringWithFormat:@"similFranzSat %@", ver];
    [self.view addSubview:_screen];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(screenTap:)];
    [_screen addGestureRecognizer:tap];
    _keys = [[OxiKeypad alloc] initWithFrame:CGRectMake(0, b.size.height - kpH, b.size.width, kpH)];
    [self.view addSubview:_keys];
    // piè di pagina: indirizzo della web app e stato del collegamento (piccolo, in basso a destra sulla scocca)
    _footer = [[UILabel alloc] initWithFrame:CGRectMake(6, b.size.height - 12, b.size.width - 12, 10)];
    _footer.backgroundColor = [UIColor clearColor]; _footer.textColor = keyBlue; _footer.font = [UIFont systemFontOfSize:8]; _footer.textAlignment = NSTextAlignmentRight;
    [self.view addSubview:_footer];
    __weak OxiViewController *weak = self;
    _keys.onKeyDown = ^(NSString *k) { [weak keyDown:k]; };
    _keys.onKeyUp = ^(NSString *k, BOOL inside) { [weak keyUp:k inside:inside]; };

    _engine = [[OxiEngine alloc] initWithSeed:(unsigned int)arc4random()];
    _sound = [OxiSound new]; [_sound start];
    _menu = [OxiMenu new]; _screen.menu = _menu;
    NSInteger pv = [[NSUserDefaults standardUserDefaults] objectForKey:kPulseVolKey] ? [[NSUserDefaults standardUserDefaults] integerForKey:kPulseVolKey] : 5;
    _menu.pulseVolume = MAX(0, MIN(10, pv)); _sound.pulseGain = _menu.pulseVolume / 10.0;
    _dateF = [NSDateFormatter new]; _dateF.dateFormat = @"dd/MM/yy"; _timeF = [NSDateFormatter new]; _timeF.dateFormat = @"HH:mm:ss";
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    _client = [OxiClient new];
    // server interno (uso autonomo): stesso schema API del monitor, console ridotta in www/index.html
    NSString *page = [[NSBundle mainBundle] pathForResource:@"index" ofType:@"html" inDirectory:@"www"];
    NSData *html = page ? [NSData dataWithContentsOfFile:page] : nil;
    if (!html) SFLog(@"console web mancante nel bundle (www/index.html)");
    _server = [[OxiServer alloc] initWithState:[OxiLocalState new] files:html ? @{ @"index.html": html } : @{}];
    _server.clock = ^NSTimeInterval { return CACurrentMediaTime(); };
    _server.state.clock = ^NSTimeInterval { return CACurrentMediaTime(); };
    _started = CACurrentMediaTime();
    [self loadClientSettings];
    _client.onState = ^(NSDictionary *st) { if (![weak isLocal]) [weak gotState:st]; };
    _client.onLink = ^(BOOL l) { SFLog(@"collegamento al monitor: %@ (%@)", l ? @"OK" : @"PERSO", weak.client.activeHost ?: @"-"); [weak refreshScreen]; };
    [_client start];
    [self startServer];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(loadClientSettings) name:NSUserDefaultsDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(stopServer) name:UIApplicationDidEnterBackgroundNotification object:nil];   // iOS sospende i socket in background
    [nc addObserver:self selector:@selector(startServer) name:UIApplicationWillEnterForegroundNotification object:nil];

    _screen.trace.sampler = ^double(NSTimeInterval t) { return [weak.engine plethAt:t]; };
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    _link.frameInterval = 2;                                   // 30 fps
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    SFLog(@"interfaccia pronta");
}
- (OxiEngine *)engine { return _engine; }
- (OxiClient *)client { return _client; }
- (OxiServer *)server { return _server; }
- (BOOL)isLocal { return _local; }

- (void)loadClientSettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *host = [[d stringForKey:@"sf_host"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSInteger port = [d integerForKey:@"sf_port"];
    _client.host = host ?: @""; _client.port = (port >= 1 && port <= 65535) ? (NSUInteger)port : 8080;
    _client.pin = [[d stringForKey:@"sf_pin"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    // server interno: modalità, porta e PIN della web app locale (generato al primo avvio)
    _mode = [d stringForKey:@"sf_mode"] ?: @"auto";
    NSString *lp = [[d stringForKey:@"sf_local_pin"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    if (lp.length < 4) { lp = [NSString stringWithFormat:@"%06u", 100000 + arc4random_uniform(900000)]; [d setObject:lp forKey:@"sf_local_pin"]; [d synchronize]; SFLog(@"PIN web app generato"); }
    _server.pin = lp;
    if (_server.running && _server.port != [self localPort]) { [self stopServer]; [self startServer]; }
}

#pragma mark - Uso autonomo (server interno)

- (uint16_t)localPort { NSInteger p = [[NSUserDefaults standardUserDefaults] integerForKey:@"sf_local_port"]; return (p >= 1024 && p <= 65535) ? (uint16_t)p : 8080; }
- (void)startServer {
    if (_server.running) return;
    NSError *err = nil;
    if ([_server startOnPort:[self localPort] error:&err]) SFLog(@"server interno attivo sulla porta %u (%@)", _server.port, [NetworkInfo wifiIPv4] ?: @"senza Wi-Fi");
    else SFLog(@"server interno NON avviato: %@", err.localizedDescription);
}
- (void)stopServer { if (_server.running) { [_server stop]; SFLog(@"server interno fermato"); } }
- (NSString *)monitorURL { return _client.activeHost.length ? [NSString stringWithFormat:@"http://%@:%lu/", _client.activeHost, (unsigned long)_client.port] : nil; }

// Comando verso chi "possiede" il paziente: il monitor (HTTP) oppure lo stato locale (in memoria, nessuna rete)
- (void)command:(NSString *)name value:(id)value {
    if (!_local) { [_client sendCommand:name value:value]; return; }
    NSString *err = nil;
    NSDictionary *cmd = value ? @{ @"command": name, @"value": value } : @{ @"command": name };
    if (![_server.state applyCommand:cmd error:&err]) SFLog(@"comando locale %@ rifiutato: %@", name, err);
    dispatch_async(dispatch_get_main_queue(), ^{ [self localPoll]; });   // mai rientrare in gotState dal chiamante
}
- (void)localPoll { if (_local) { _lastLocalPoll = CACurrentMediaTime(); [self gotState:[_server.state stateDictionary]]; } }

// nome fisso in rete (Bonjour): iOS lo ricava dal nome del dispositivo ("similFranzSat" -> similfranzsat.local)
static NSString *LocalHostName(void) {
    NSString *n = [UIDevice currentDevice].name ?: @"";
    NSMutableString *h = [NSMutableString string];
    for (NSUInteger i = 0; i < n.length; i++) {
        unichar c = [n characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-') [h appendFormat:@"%C", c];
        else if (c == ' ' && h.length && ![h hasSuffix:@"-"]) [h appendString:@"-"];
    }
    return h.length ? [[h lowercaseString] stringByAppendingString:@".local"] : nil;
}

// Ogni 0,5 s: decide chi comanda. Monitor in rete -> client del monitor; altrimenti (dopo 8 s dall'avvio, o 15 s
// senza risposte) -> autonomo. "Solo iPod" nelle Impostazioni forza l'autonomo.
- (void)refreshChrome {
    UIDevice *dev = [UIDevice currentDevice];
    _battery.level = dev.batteryLevel < 0 ? 1 : dev.batteryLevel;
    _battery.charging = dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull;
    NSString *ip = [NetworkInfo wifiIPv4], *t;
    // regia collegata = qualcuno dialoga con il saturimetro: in autonomo una web app/app che ha interrogato il server negli ultimi 6 s,
    // da collegato il monitor (e la sua console) che risponde
    BOOL regia = _local ? (_server.lastClientAt > 0 && CACurrentMediaTime() - _server.lastClientAt < 6) : _client.linked;
    _wifi.state = !ip ? 0 : regia ? 2 : 1;
    if (!ip) t = @"Wi-Fi non collegato";
    else if (_local) t = [NSString stringWithFormat:@"autonomo · %@ · %@:%u · %@", regia ? @"regia collegata" : @"nessuna regia", LocalHostName() ?: ip, _server.port ?: [self localPort], ip];
    else if (_client.linked) t = [NSString stringWithFormat:@"collegato al monitor %@ · web app http://%@:%lu", _client.activeHost, _client.activeHost, (unsigned long)_client.port];
    else t = [NSString stringWithFormat:@"ricerca del monitor… · iPod %@", ip];
    if (![t isEqualToString:_footer.text]) _footer.text = t;
}

- (void)modeTick:(NSTimeInterval)now {
    [self refreshChrome];
    // abbinamento diretto: appena un telefono apre la console dal QR, l'iPod esce dal menu e resta spento, pronto per lo scenario
    if (_menu.page == OxiMenuPair && _lastPage != OxiMenuPair) _pairOpenedAt = now;
    _lastPage = _menu.page;
    if (_menu.page == OxiMenuPair && _local && _server.pairedAt > _pairOpenedAt) {
        SFLog(@"abbinamento diretto riuscito: esco dal menu, saturimetro spento");
        [_sound keyClick];
        [_menu close]; _lastPage = OxiMenuClosed;
        if (_powered) [self powerOffSend:YES];
        else { _powerGuardUntil = now + 3; [self command:@"set_oximeter" value:@{ @"power": @NO }]; }
        [self command:@"set_sensor" value:@{ @"sensor": @"oxi", @"connected": @NO }];
        _screen.menu = _menu; [_screen refresh];
        return;
    }
    if (_menu.page == OxiMenuInfo || _menu.page == OxiMenuPair || _menu.page == OxiMenuEco) {   // pagine di stato: aggiornate dal vivo
        NSString *before = [NSString stringWithFormat:@"%@|%@|%@|%@", _menu.infoLines, _menu.pairURL, _menu.pairNote, _menu.ecoLines];
        [self fillInfo];
        if (![before isEqualToString:[NSString stringWithFormat:@"%@|%@|%@|%@", _menu.infoLines, _menu.pairURL, _menu.pairNote, _menu.ecoLines]]) [_screen refresh];
    }
    BOOL force = [_mode isEqualToString:@"solo"], remote = _client.linked;
    if (!_local) {
        NSTimeInterval since = _client.secondsSinceOK;
        BOOL giveUp = !remote && (since < 0 ? now - _started > 8 : since > 15);
        if (force || giveUp) {
            _local = YES; _server.monitorURL = nil;
            SFLog(@"modalità AUTONOMA (%@): web app su http://%@:%u/", force ? @"impostazione" : @"monitor non trovato", [NetworkInfo wifiIPv4] ?: @"?", _server.port);
            NSString *e = nil;   // lo stato fisico del dispositivo vince: il paziente locale parte allineato
            [_server.state applyCommand:@{ @"command": @"set_oximeter", @"value": @{ @"power": @(_powered) } } error:&e];
            [_server.state applyCommand:@{ @"command": @"set_sensor", @"value": @{ @"sensor": @"oxi", @"connected": @NO } } error:&e];
            _firstState = YES; [self localPoll]; [self refreshScreen];
        }
        return;
    }
    if (remote && !force) {
        _local = NO; _server.monitorURL = [self monitorURL];
        SFLog(@"modalità COLLEGATA al monitor %@", _server.monitorURL);
        _powerGuardUntil = now + 3; [_client sendCommand:@"set_oximeter" value:@{ @"power": @(_powered) }];
        [_client sendCommand:@"set_sensor" value:@{ @"sensor": @"oxi", @"connected": @NO }];
        [self refreshScreen];
    }
}

#pragma mark - Stato dal monitor

- (void)gotState:(NSDictionary *)st {
    OxiPatient *p = st ? [OxiPatient patientFromState:st] : _patient;
    if (!p) return;
    NSTimeInterval now = CACurrentMediaTime();
    _patient = p; _patientAt = now;
    if (!_firstState) {                                        // il dispositivo parte SEMPRE spento: allineo il controller
        _firstState = YES;
        if (p.remotePower && !_powered) { _powerGuardUntil = now + 3; [self command:@"set_oximeter" value:@{ @"power": @NO }]; p.remotePower = NO; SFLog(@"avvio da spento: il controller lo ricordava acceso"); }
    }
    // accensione comandata dal controller (dopo una modifica locale ignoro per 3 s la vecchia eco del server)
    if (now > _powerGuardUntil && p.remotePower != _powered) {
        SFLog(@"accensione dal controller: %@", p.remotePower ? @"ON" : @"OFF");
        if (p.remotePower) [self powerOnSend:NO]; else [self powerOffSend:NO];
    }
    if (now > _limitsGuardUntil && !(_menu.page == OxiMenuLimits && _menu.editing)) _menu.limits = p.limits;
    if (now > _volGuardUntil) { _menu.alarmVolume = MAX(1, MIN(10, (p.volume + 5) / 10)); _sound.alarmGain = p.volume / 100.0; }
    if (now > _muteGuardUntil) _localMute = p.mutedRemaining;
    p.delaySec = 0;                                            // il ritardo lo gestisce il dispositivo (sotto), non il monitor
    OxiSignal sig = OxiSignalFor(p);
    if (sig == OxiSignalOK && _baseSig != OxiSignalOK) {        // segnale appena tornato buono: ricerca del polso (scelta dall'istruttore, o casuale 5-10 s)
        _acqStart = now; _acqDelay = p.acquireSec > 0 ? (double)p.acquireSec : 5.0 + arc4random_uniform(501) / 100.0;
        SFLog(@"acquisizione: %.1f s", _acqDelay);
    }
    _baseSig = sig;
    if (sig == OxiSignalOK && now - _acqStart < _acqDelay) sig = (now - _acqStart < _acqDelay * 0.4) ? OxiSignalSearching : OxiSignalAcquiring;
    if (sig != _sig) {
        SFLog(@"segnale: %ld -> %ld", (long)_sig, (long)sig);
        if (sig == OxiSignalSearching) _searchSince = now;
        if (sig == OxiSignalNoPulse) _noPulseSince = now;
        _sig = sig;
        [_screen.trace resetAtTime:now];
    }
    [_engine updateWithPatient:p signal:sig];
    [self evaluateAt:now];
}

- (void)evaluateAt:(NSTimeInterval)now {
    _lastEval = now;
    OxiPatient *p = _patient;
    BOOL stale = !p || now - _patientAt > 4;                  // nessuna risposta dal monitor
    if (!_powered) { [_sound setAlarm:OxiAlarmNone]; return; }
    OxiSignal sig = stale ? OxiSignalSensorOff : _sig;
    _alarm = stale ? nil : OxiEvaluate(p, sig, sig == OxiSignalNoPulse ? now - _noPulseSince : 0, sig == OxiSignalSearching ? now - _searchSince : 0);
    // testi
    NSString *spo2 = @"---", *pr = @"---";
    if (!stale && sig == OxiSignalOK) {
        NSInteger sv = MIN(100, MAX(0, p.spo2 + (NSInteger)lround(_jSp))), pv = MAX(1, p.pulseRate + (NSInteger)lround(_jPr));
        spo2 = [NSString stringWithFormat:@"%ld", (long)sv]; pr = [NSString stringWithFormat:@"%ld", (long)pv];
        if (p.lowPerfusion || p.lowPerfFlag) {                // "?" al posto del valore per 4 s, poi il valore per 2 s
            if (_lowPerfSince == 0) _lowPerfSince = now;
            if (fmod(now - _lowPerfSince, 6.0) < 4.0) spo2 = @"?";
        } else _lowPerfSince = 0;
    } else _lowPerfSince = 0;
    _screen.spo2Text = spo2; _screen.prText = pr;
    _screen.searching = (sig == OxiSignalSearching);
    _screen.sensorOn = !stale && p.sensorConnected;
    _screen.spo2Low = [p limit:@"spo2_low"] ?: 85; _screen.spo2High = [p limit:@"spo2_high"] ?: 100;
    _screen.prLow = [p limit:@"pr_low"] ?: 30; _screen.prHigh = [p limit:@"pr_high"] ?: 170;
    _screen.spo2LowHit = _alarm.spo2LowViolated; _screen.spo2HighHit = _alarm.spo2HighViolated;
    _screen.prLowHit = _alarm.prLowViolated; _screen.prHighHit = _alarm.prHighViolated;
    _screen.spo2Flash = _alarm.spo2Level; _screen.prFlash = _alarm.prLevel;
    // messaggi: ruotano ogni 3 s se più di uno
    NSArray *msgs = stale ? @[@"NESSUN COLLEGAMENTO"] : _alarm.messages;
    if (msgs.count == 0) { _screen.message = nil; _msgIndex = 0; }
    else {
        if (now > _msgRotateAt) { _msgRotateAt = now + 3; _msgIndex = (_msgIndex + 1) % (NSInteger)msgs.count; }
        if (_msgIndex >= (NSInteger)msgs.count) _msgIndex = 0;
        _screen.message = msgs[(NSUInteger)_msgIndex];
        _screen.messageLevel = _msgIndex == 0 ? _alarm.level : OxiAlarmLow;
        if (stale) _screen.messageLevel = OxiAlarmLow;
    }
    NSInteger muted = _localMute;
    _screen.mutedRemaining = muted;
    [_sound setAlarm:(muted > 0 || stale) ? OxiAlarmNone : _alarm.level];
    [_screen refresh];
}

#pragma mark - Ciclo a 30 fps

- (void)frame:(CADisplayLink *)link {
    NSTimeInterval now = CACurrentMediaTime();
    // chi comanda (monitor o server interno) e stato locale: anche da spento, altrimenti la web app non accende
    if (now - _lastLocalPoll >= 0.5) { _lastLocalPoll = now; [self modeTick:now]; if (_local) [self gotState:[_server.state stateDictionary]]; }
    if (_bootStart > 0) {
        double pr = (now - _bootStart) / 2.5;
        if (pr >= 1) { _bootStart = 0; _screen.bootProgress = -1; [_screen.trace resetAtTime:now]; SFLog(@"acceso"); }
        else { _screen.bootProgress = pr; return; }
    }
    if (!_powered) return;
    BOOL menuOpen = _menu.page != OxiMenuClosed;
    if (!menuOpen) [_screen.trace advanceTo:now];
    _screen.pulseAmp = [_engine plethAt:now] / 0.9;                              // la barra si riempie e si svuota con l'onda
    // tono del polso: al battito perfuso (+0,22 s di transito fino al dito)
    if (_sig == OxiSignalOK || _sig == OxiSignalAcquiring) {
        NSTimeInterval b = [_engine lastPerfusedBeatAtOrBefore:now + 0.04 - 0.22];
        if (b >= 0 && b + 0.22 > _lastBeep + 0.05 && now - (b + 0.22) < 0.2) {
            _lastBeep = b + 0.22;
            [_sound beep:(_sig == OxiSignalOK ? OxiBeepFrequency(_patient.spo2) : 660.0)];
        }
    }
    // valori mostrati: piccola variabilità ogni ~2 s (SpO2 ±1, polso ±2)
    if (now - _lastJitter > 2.0) {
        _lastJitter = now; _jSp = (arc4random_uniform(4) == 0) ? ((arc4random_uniform(2) ? 1 : -1) * 0.6) : 0; _jPr = (arc4random_uniform(3) == 0) ? (arc4random_uniform(2) ? 1 : -1) : 0;
        [self evaluateAt:now];
    } else if (now - _lastEval > 0.5) [self evaluateAt:now];
    if (_baseSig == OxiSignalOK && _sig != OxiSignalOK && now - _acqStart >= _acqDelay && _patient) [self gotState:nil];   // fine acquisizione
    // silenziamento locale che scade
    if (_localMute > 0 && now - _lastClock >= 1.0) _localMute = MAX(0, _localMute - 1);
    if (now - _lastClock >= 1.0) {
        _lastClock = now;
        NSDate *d = [NSDate date];
        _screen.dateText = [_dateF stringFromDate:d]; _screen.timeText = [_timeF stringFromDate:d];
        UIDevice *dev = [UIDevice currentDevice];
        _screen.battery = dev.batteryLevel < 0 ? 1 : dev.batteryLevel;
        _screen.charging = dev.batteryState == UIDeviceBatteryStateCharging || dev.batteryState == UIDeviceBatteryStateFull;
        _screen.linked = _client.linked || _local;
        _screen.mutedRemaining = _localMute;
        [_screen refresh];
    }
    // lampeggio: 2 Hz alta priorità, 1 Hz media
    BOOL anyFlash = _alarm.level >= OxiAlarmMedium;
    BOOL phase = anyFlash ? (fmod(now, _alarm.level == OxiAlarmHigh ? 0.5 : 1.0) < (_alarm.level == OxiAlarmHigh ? 0.25 : 0.5)) : NO;
    if (phase != _flashOn) { _flashOn = phase; _screen.flashOn = phase; [_screen refresh]; }
}

- (void)refreshScreen { _screen.linked = _client.linked || _local; [_screen refresh]; }

#pragma mark - Accensione

- (void)powerOnSend:(BOOL)send {
    if (_powered) return;
    _powered = YES; _bootStart = CACurrentMediaTime(); _localMute = 0; _msgIndex = 0; [_menu close];
    _screen.powered = YES; _screen.bootProgress = 0; _keys.powerLed = YES;
    [_sound powerChime];
    SFLog(@"accensione (%@)", send ? @"tasto" : @"controller");
    [self command:@"set_sensor" value:@{ @"sensor": @"oxi", @"connected": @NO }];   // si riaccende sempre con la sonda staccata
    if (send) { _powerGuardUntil = CACurrentMediaTime() + 3; [self command:@"set_oximeter" value:@{ @"power": @YES }]; }
}
- (void)powerOffSend:(BOOL)send {
    if (!_powered) return;
    _powered = NO; _bootStart = 0; [_menu close];
    _screen.powered = NO; _screen.bootProgress = -1; _keys.powerLed = NO;
    [_sound setAlarm:OxiAlarmNone];
    SFLog(@"spegnimento (%@)", send ? @"tasto" : @"controller");
    if (send) { _powerGuardUntil = CACurrentMediaTime() + 3; [self command:@"set_oximeter" value:@{ @"power": @NO }]; }
}

#pragma mark - Tasti

- (void)keyDown:(NSString *)k {
    [_sound keyClick];
    if ([k isEqualToString:@"power"]) {
        // come sui saturimetri palmari: tenere premuto ~1 s per accendere o spegnere
        [_powerTimer invalidate];
        _powerTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(powerHeld) userInfo:nil repeats:NO];
    }
}
- (void)powerHeld { _powerTimer = nil; if (_powered) [self powerOffSend:YES]; else [self powerOnSend:YES]; }
- (void)keyUp:(NSString *)k inside:(BOOL)inside {
    if ([k isEqualToString:@"power"]) { [_powerTimer invalidate]; _powerTimer = nil; return; }
    if (!inside || _bootStart > 0) return;
    if (!_powered && !([k isEqualToString:@"menu"] || _menu.page != OxiMenuClosed)) return;   // da spento: solo il menu (≡ e le sue frecce)
    NSTimeInterval now = CACurrentMediaTime();
    if ([k isEqualToString:@"mute"]) {
        if (_menu.page != OxiMenuClosed) return;
        BOOL unmute = _localMute > 0;
        _localMute = unmute ? 0 : 120; _muteGuardUntil = now + 3;
        SFLog(@"silenziamento: %@", unmute ? @"annullato" : @"2 min");
        [self command:@"set_oximeter" value:@{ @"mute_s": @(unmute ? 0 : 120) }];
        [self evaluateAt:now];
        return;
    }
    if ([k isEqualToString:@"menu"]) {
        if (_menu.page == OxiMenuClosed) { [self fillInfo]; [_menu open]; } else [_menu close];
        _screen.menu = _menu; [_screen refresh];
        return;
    }
    if (_menu.page == OxiMenuClosed) return;                  // ▲▼✓↩ servono solo nel menu
    OxiMenuAction a = [_menu key:k];
    [self fillInfo];
    switch (a) {
        case OxiMenuLimitsChanged:
            _limitsGuardUntil = now + 3; SFLog(@"limiti: %@", _menu.limits);
            [self command:@"set_oximeter" value:@{ @"alarm_limits": _menu.limits }];
            break;
        case OxiMenuPulseVolChanged:
            _sound.pulseGain = _menu.pulseVolume / 10.0;
            [[NSUserDefaults standardUserDefaults] setInteger:_menu.pulseVolume forKey:kPulseVolKey]; [[NSUserDefaults standardUserDefaults] synchronize];
            [_sound beep:880];
            break;
        case OxiMenuAlarmVolChanged:
            _volGuardUntil = now + 3; _sound.alarmGain = _menu.alarmVolume / 10.0;
            [self command:@"set_oximeter" value:@{ @"volume": @(_menu.alarmVolume * 10) }];
            break;
        case OxiMenuResetScenario:                                 // come il tasto rosso del monitor: azzera il paziente e spegne tutto
            SFLog(@"azzera scenario e spegni (menu)");
            [self command:@"reset_scenario" value:nil];
            [self powerOffSend:NO]; [_menu close]; _screen.menu = _menu; [_screen refresh];
            return;
        default: break;
    }
    _screen.menu = _menu; [_screen refresh];
}
// Tocco sullo schermo (come i tocchi nascosti del monitor): sul pletismo applica il sensore; sul valore SpO2 o polso
// applica il sensore se manca (compaiono i valori), altrimenti apre i limiti di quel parametro. Mai scollega.
- (void)screenTap:(UITapGestureRecognizer *)g {
    if (!_powered || _bootStart > 0 || _menu.page != OxiMenuClosed) return;
    [self screenZone:[_screen zoneAtPoint:[g locationInView:_screen]]];
}
- (void)screenZone:(NSString *)zone {
    if (!zone) return;
    BOOL sensor = _patient.sensorConnected;
    if (!sensor) {
        SFLog(@"tocco su %@: applico il sensore", zone);
        [self command:@"set_sensor" value:@{ @"sensor": @"oxi", @"connected": @YES, @"site": @"finger_r2" }];
        return;
    }
    if ([zone isEqualToString:@"pleth"]) return;
    [_sound keyClick];
    [_menu openLimitsAt:([zone isEqualToString:@"pr"] ? 2 : 0)];
    _screen.menu = _menu; [_screen refresh];
}

- (void)fillInfo {
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    _menu.infoLines = @[ [NSString stringWithFormat:@"similFranzSat %@", ver],
                         @"Simulazione — non per uso clinico",
                         _local ? @"Modalità: AUTONOMO (server interno)" : (_client.linked ? @"Modalità: collegato al monitor" : @"Modalità: ricerca del monitor…"),
                         [NSString stringWithFormat:@"Monitor: %@", _client.activeHost.length ? [NSString stringWithFormat:@"%@:%lu %@", _client.activeHost, (unsigned long)_client.port, _client.linked ? @"OK" : (_client.lastError ?: @"")] : @"non trovato"],
                         [NSString stringWithFormat:@"PIN monitor: %@", _client.pin.length ? @"impostato" : @"MANCANTE (Impostazioni)"],
                         [NSString stringWithFormat:@"Web app: http://%@:%u/", LocalHostName() ?: @"-", _server.port ?: [self localPort]],
                         [NSString stringWithFormat:@"  oppure http://%@:%u/", [NetworkInfo wifiIPv4] ?: @"(no Wi-Fi)", _server.port ?: [self localPort]],
                         [NSString stringWithFormat:@"PIN web app: %@", _server.pin ?: @"-"],
                         [NSString stringWithFormat:@"Sensore: %@", _patient.sensorConnected ? @"applicato" : @"non applicato"],
                         [NSString stringWithFormat:@"Batteria: %.0f %%", MAX(0, [UIDevice currentDevice].batteryLevel) * 100] ];
    // abbinamento diretto: il QR porta all'indirizzo numerico (funziona su ogni telefono) e al PIN già inserito
    NSString *ip = [NetworkInfo wifiIPv4];
    _menu.pairURL = ip ? [NSString stringWithFormat:@"http://%@:%u/#pin=%@", ip, _server.port ?: [self localPort], _server.pin ?: @""] : nil;
    _menu.pairPIN = _server.pin;
    _menu.pairNote = (!_local && _client.linked) ? @"Ora è collegato al monitor:\ncomandi dalla sua console." : nil;
    _menu.ecoLines = @[ [NSString stringWithFormat:@"Stato: %@", _local ? @"autonomo (monitor non trovato)" : (_client.linked ? @"COLLEGATO al monitor" : @"ricerca del monitor…")],
                        [NSString stringWithFormat:@"Monitor: %@", _client.activeHost.length ? [NSString stringWithFormat:@"%@:%lu", _client.activeHost, (unsigned long)_client.port] : @"non trovato"],
                        [NSString stringWithFormat:@"PIN monitor: %@", _client.pin.length ? @"impostato" : @"MANCANTE (Impostazioni › similFranzSat)"],
                        [NSString stringWithFormat:@"Wi-Fi: %@", ip ?: @"non collegato"],
                        @"Senza monitor per 8 s all'avvio lavora da solo",
                        @"e torna al monitor appena ricompare." ];
}

#pragma mark - Verifica da Mac (URL simulafranz-saturimetro://)

- (void)debugTap:(NSString *)key {
    if ([key isEqualToString:@"power_long"]) { [_sound keyClick]; if (_powered) [self powerOffSend:YES]; else [self powerOnSend:YES]; return; }
    if ([key hasPrefix:@"tap_"]) { if (_powered && _bootStart <= 0 && _menu.page == OxiMenuClosed) [self screenZone:[key substringFromIndex:4]]; return; }
    [_keys pressKey:key];
}
- (void)saveShot:(NSString *)name {
    UIWindow *w = self.view.window; if (!w) return;
    UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0);
    [w.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    NSString *dir = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"shots"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
    [UIImagePNGRepresentation(img) writeToFile:path atomically:YES];
    SFLog(@"screenshot %@", path);
}
- (void)runSelfTest {
    // accensione, schermata principale, menu, limiti, volume, info, spegnimento: uno screenshot per passo
    _stSteps = @[ @[@"power_long", @"00_boot"], @[@"", @"01_main"], @[@"menu", @"02_menu"], @[@"ok", @"03_limits"], @[@"ok", @"04_limits_edit"],
                  @[@"down", @"05_limits_edit_down"], @[@"back", @"06_limits"], @[@"back", @"07_menu"], @[@"down", @"08_menu_2"], @[@"ok", @"09_pulsevol"],
                  @[@"back", @"10_menu"], @[@"down", @"11_menu_3"], @[@"down", @"12_menu_4"], @[@"ok", @"13_info"], @[@"back", @"14_menu"],
                  @[@"menu", @"15_main"], @[@"mute", @"16_muted"], @[@"mute", @"17_unmuted"], @[@"power_long", @"18_off"] ];
    _stIndex = 0;
    SFLog(@"autotest: inizio (%lu passi)", (unsigned long)_stSteps.count);
    [self selfTestStep];
}
- (void)selfTestStep {
    if (_stIndex >= _stSteps.count) { SFLog(@"autotest: fine"); _stSteps = nil; return; }
    NSArray *s = _stSteps[_stIndex++];
    if ([s[0] length]) [self debugTap:s[0]];
    NSTimeInterval wait = [s[1] isEqualToString:@"00_boot"] ? 1.2 : ([s[1] isEqualToString:@"01_main"] ? 3.0 : 0.6);
    __weak OxiViewController *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weak saveShot:s[1]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weak selfTestStep]; });
    });
}
@end
