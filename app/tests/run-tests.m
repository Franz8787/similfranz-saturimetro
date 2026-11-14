// Test di logica su macOS (Foundation): stato, segnale, allarmi, menu, battiti/pleth.
#import <Foundation/Foundation.h>
#import "OxiState.h"
#import "OxiEngine.h"
#import "OxiLocalState.h"
#import "OxiServer.h"
#import "OxiUpdate.h"
#include <zlib.h>
static int passed = 0, failed = 0;
#define CHECK(cond, msg) do { if (cond) passed++; else { failed++; printf("FALLITO: %s (riga %d)\n", msg, __LINE__); } } while (0)

static NSDictionary *state(NSDictionary *over) {
    NSMutableDictionary *s = [@{ @"spo2_percent": @97, @"pulse_rate_bpm": @80, @"heart_rate_bpm": @80, @"systolic_mmhg": @120,
        @"pulse_present": @YES, @"spo2_signal_valid": @YES, @"spo2_low_perfusion": @NO, @"spo2_low_perfusion_flag": @NO,
        @"cpr_active": @NO, @"simulation_running": @YES, @"patient_motion": @"off", @"rhythm": @"sinus", @"spo2_delay_s": @0, @"revision": @5,
        @"oximeter": @{ @"power": @YES, @"sensor_connected": @YES, @"sensor_since_s": @30, @"cuff_occluded": @NO, @"volume": @70,
                        @"muted_remaining_s": @0, @"alarm_limits": @{ @"spo2_low": @85, @"spo2_high": @100, @"pr_low": @30, @"pr_high": @170 } } } mutableCopy];
    [s addEntriesFromDictionary:over];
    return s;
}
static NSDictionary *oxi(NSDictionary *base, NSDictionary *over) {
    NSMutableDictionary *o = [base[@"oximeter"] mutableCopy]; [o addEntriesFromDictionary:over];
    NSMutableDictionary *s = [base mutableCopy]; s[@"oximeter"] = o; return s;
}

// --- per i test degli aggiornamenti: un .deb minimo costruito qui (ar + control.tar.gz con ./control) ---
static NSData *TestGzip(NSData *d) {
    z_stream z; memset(&z, 0, sizeof z); deflateInit2(&z, 9, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY);
    NSMutableData *o = [NSMutableData dataWithLength:d.length + 1024];
    z.next_in = (Bytef *)d.bytes; z.avail_in = (uInt)d.length; z.next_out = o.mutableBytes; z.avail_out = (uInt)o.length;
    deflate(&z, Z_FINISH); o.length = z.total_out; deflateEnd(&z); return o;
}
static NSData *TestDeb(NSString *control) {
    NSData *c = [control dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *tar = [NSMutableData dataWithLength:512];
    char *h = tar.mutableBytes; strcpy(h, "./control"); strcpy(h + 100, "0000644"); snprintf(h + 124, 12, "%011lo", (unsigned long)c.length); h[156] = '0';
    [tar appendData:c]; tar.length = 512 + (c.length + 511) / 512 * 512 + 1024;
    NSData *gz = TestGzip(tar);
    NSMutableData *deb = [[@"!<arch>\n" dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    NSArray *members = @[@[@"debian-binary", [@"2.0\n" dataUsingEncoding:NSASCIIStringEncoding]], @[@"control.tar.gz", gz]];
    for (NSArray *m in members) {
        NSData *d = m[1];
        [deb appendData:[[NSString stringWithFormat:@"%-16s%-12d%-6d%-6d%-8s%-10lu`\n", [m[0] UTF8String], 0, 0, 0, "100644", (unsigned long)d.length] dataUsingEncoding:NSASCIIStringEncoding]];
        [deb appendData:d]; if (d.length % 2) [deb appendBytes:"\n" length:1];
    }
    return deb;
}

int main(void) { @autoreleasepool {
    // --- parsing ---
    CHECK([OxiPatient patientFromState:@{}] == nil, "stato vuoto -> nil");
    OxiPatient *p = [OxiPatient patientFromState:state(@{})];
    CHECK(p.spo2 == 97 && p.pulseRate == 80 && p.sensorConnected && p.sensorSince == 30, "parsing base");
    CHECK([p limit:@"spo2_low"] == 85 && [p limit:@"pr_high"] == 170, "limiti");
    // --- segnale ---
    CHECK(OxiSignalFor(p) == OxiSignalOK, "segnale ok");
    OxiPatient *q = [OxiPatient patientFromState:oxi(state(@{}), @{ @"sensor_connected": @NO })];
    CHECK(OxiSignalFor(q) == OxiSignalSensorOff, "sensore scollegato");
    q = [OxiPatient patientFromState:oxi(state(@{ @"spo2_delay_s": @20 }), @{ @"sensor_since_s": @3 })];
    CHECK(OxiSignalFor(q) == OxiSignalSearching, "ricerca polso nella prima metà del ritardo");
    q = [OxiPatient patientFromState:oxi(state(@{ @"spo2_delay_s": @20 }), @{ @"sensor_since_s": @15 })];
    CHECK(OxiSignalFor(q) == OxiSignalAcquiring, "acquisizione nella seconda metà");
    q = [OxiPatient patientFromState:state(@{ @"pulse_present": @NO, @"rhythm": @"vf" })];
    CHECK(OxiSignalFor(q) == OxiSignalNoPulse, "nessun polso");
    q = [OxiPatient patientFromState:state(@{ @"spo2_signal_valid": @NO })];
    CHECK(OxiSignalFor(q) == OxiSignalInterference, "segnale assente -> interferenza");
    q = [OxiPatient patientFromState:state(@{ @"pulse_rate_bpm": @3 })];
    CHECK(OxiSignalFor(q) == OxiSignalNoPulse, "polso 3 bpm (rampa dal ROSC) -> ricerca, mai '1'");
    q = [OxiPatient patientFromState:state(@{ @"spo2_percent": @12 })];
    CHECK(OxiSignalFor(q) == OxiSignalNoPulse, "SpO2 12% -> ricerca, mai un numero da 0");
    q = [OxiPatient patientFromState:oxi(state(@{}), @{ @"cuff_occluded": @YES })];
    CHECK(OxiSignalFor(q) == OxiSignalInterference, "bracciale stesso braccio -> interferenza");
    // --- allarmi ---
    OxiAlarmResult *a = OxiEvaluate(p, OxiSignalOK, 0, 0);
    CHECK(a.level == OxiAlarmNone && a.messages.count == 0, "nessun allarme a 97%");
    q = [OxiPatient patientFromState:state(@{ @"spo2_percent": @83 })];
    a = OxiEvaluate(q, OxiSignalOK, 0, 0);
    CHECK(a.level == OxiAlarmMedium && a.spo2LowViolated && [a.messages[0] isEqualToString:@"SpO2 BASSA < 85"], "SpO2 83 -> medio");
    q = [OxiPatient patientFromState:state(@{ @"spo2_percent": @75 })];
    a = OxiEvaluate(q, OxiSignalOK, 0, 0);
    CHECK(a.level == OxiAlarmHigh && a.spo2Level == OxiAlarmHigh, "SpO2 75 -> alto");
    q = [OxiPatient patientFromState:state(@{ @"pulse_rate_bpm": @180 })];
    a = OxiEvaluate(q, OxiSignalOK, 0, 0);
    CHECK(a.level == OxiAlarmMedium && a.prHighViolated, "polso 180 -> medio");
    q = [OxiPatient patientFromState:state(@{ @"pulse_rate_bpm": @15 })];
    a = OxiEvaluate(q, OxiSignalOK, 0, 0);
    CHECK(a.level == OxiAlarmHigh && a.prLowViolated, "polso 15 -> alto");
    a = OxiEvaluate(p, OxiSignalNoPulse, 3, 0);
    CHECK(a.level == OxiAlarmLow && [a.messages[0] isEqualToString:@"RICERCA POLSO"], "senza polso da 3 s: ricerca");
    a = OxiEvaluate(p, OxiSignalNoPulse, 12, 0);
    CHECK(a.level == OxiAlarmHigh && [a.messages[0] isEqualToString:@"POLSO PERSO"], "senza polso da 12 s: polso perso");
    a = OxiEvaluate(p, OxiSignalSensorOff, 0, 0);
    CHECK(a.level == OxiAlarmLow && [a.messages[0] isEqualToString:@"SENSORE SCOLLEGATO"], "sensore scollegato: tecnico");
    q = [OxiPatient patientFromState:state(@{ @"spo2_low_perfusion": @YES, @"patient_motion": @"light" })];
    a = OxiEvaluate(q, OxiSignalOK, 0, 0);
    CHECK(a.level == OxiAlarmLow && a.messages.count == 2, "bassa perfusione + movimento: due messaggi tecnici");
    q = [OxiPatient patientFromState:state(@{ @"simulation_running": @NO, @"spo2_percent": @60 })];
    CHECK(OxiEvaluate(q, OxiSignalOK, 0, 0).level == OxiAlarmNone, "in pausa niente allarmi");
    CHECK(fabs(OxiBeepFrequency(100) - 880) < 0.01 && OxiBeepFrequency(90) < 700 && OxiBeepFrequency(90) > 690, "tono del polso");
    // --- menu ---
    OxiMenu *m = [OxiMenu new];
    CHECK(m.page == OxiMenuClosed, "menu chiuso");
    [m open]; CHECK(m.page == OxiMenuMain && m.cursor == 0, "menu aperto");
    [m key:@"up"]; CHECK(m.cursor == 6, "su dal primo -> ultimo");
    [m key:@"ok"]; CHECK(m.page == OxiMenuClosed, "Esci chiude");
    [m open]; for (int i = 0; i < 3; i++) [m key:@"down"]; [m key:@"ok"]; CHECK(m.page == OxiMenuConnect && m.cursor == 0, "sottomenu Collegamento");
    [m key:@"ok"]; CHECK(m.page == OxiMenuPair, "pagina abbinamento diretto");
    [m key:@"ok"]; CHECK(m.page == OxiMenuConnect && m.cursor == 0, "abbinamento -> Collegamento");
    [m key:@"down"]; [m key:@"ok"]; CHECK(m.page == OxiMenuEco, "pagina ecosistema monitor");
    [m key:@"back"]; CHECK(m.page == OxiMenuConnect && m.cursor == 1, "ecosistema -> Collegamento");
    [m key:@"down"]; [m key:@"ok"]; CHECK(m.page == OxiMenuMain && m.cursor == 3, "Indietro -> menu sulla voce Collegamento");
    [m close]; [m open]; [m key:@"ok"]; CHECK(m.page == OxiMenuLimits && !m.editing, "pagina limiti");
    [m key:@"ok"]; CHECK(m.editing, "modifica SpO2 alto");
    [m key:@"down"]; CHECK([m.limits[@"spo2_high"] integerValue] == 99, "SpO2 alto 100 -> 99");
    OxiMenuAction act = [m key:@"ok"]; CHECK(act == OxiMenuLimitsChanged && !m.editing, "conferma -> azione limiti");
    [m key:@"down"]; [m key:@"ok"]; for (int i = 0; i < 30; i++) [m key:@"up"];
    CHECK([m.limits[@"spo2_low"] integerValue] == 98, "SpO2 basso non supera l'alto - 1");
    [m key:@"back"]; CHECK(!m.editing && m.page == OxiMenuLimits, "indietro annulla la modifica");
    [m key:@"down"]; [m key:@"ok"]; [m key:@"up"]; CHECK([m.limits[@"pr_high"] integerValue] == 175, "polso alto a passi di 5");
    [m key:@"ok"]; [m key:@"down"]; [m key:@"down"]; [m key:@"ok"]; CHECK(m.page == OxiMenuMain, "Indietro dalla pagina limiti");
    [m key:@"down"]; [m key:@"ok"]; CHECK(m.page == OxiMenuPulseVol, "pagina volume polso");
    act = [m key:@"up"]; CHECK(act == OxiMenuPulseVolChanged && m.pulseVolume == 6, "volume polso +1");
    [m key:@"back"]; [m key:@"down"]; [m key:@"ok"]; CHECK(m.page == OxiMenuAlarmVol, "pagina volume allarmi");
    for (int i = 0; i < 20; i++) [m key:@"down"]; CHECK(m.alarmVolume == 1, "volume allarmi minimo 1");
    [m key:@"back"]; [m key:@"down"]; [m key:@"down"]; [m key:@"ok"]; CHECK(m.page == OxiMenuInfo, "pagina info");
    [m key:@"back"]; [m key:@"back"]; CHECK(m.page == OxiMenuClosed, "indietro due volte chiude");
    [m openLimitsAt:2]; CHECK(m.page == OxiMenuLimits && m.cursor == 2 && !m.editing, "limiti aperti sul polso alto");
    [m close]; [m open]; [m key:@"up"]; [m key:@"up"]; CHECK(m.cursor == 5, "voce Azzera scenario");
    [m key:@"ok"]; CHECK(m.page == OxiMenuConfirmReset, "pagina di conferma");
    [m key:@"back"]; CHECK(m.page == OxiMenuMain && m.cursor == 5, "annulla torna al menu");
    [m key:@"ok"]; act = [m key:@"ok"]; CHECK(act == OxiMenuResetScenario && m.page == OxiMenuClosed, "conferma -> azione reset, menu chiuso");
    // --- motore: battiti e pleth ---
    OxiEngine *e = [[OxiEngine alloc] initWithSeed:3];
    [e updateWithPatient:p signal:OxiSignalOK];
    int beats = 0; NSTimeInterval last = -1; double mx = 0;
    for (double t = 0; t < 30; t += 0.01) {
        double v = [e plethAt:t]; mx = MAX(mx, v);
        NSTimeInterval b = [e lastPerfusedBeatAtOrBefore:t];
        if (b > last + 0.05) { if (last >= 0) beats++; last = b; }
    }
    CHECK(beats >= 36 && beats <= 42, "~80 bpm: 36-42 battiti in 30 s");
    CHECK(mx > 0.3 && mx <= 1.1, "ampiezza pleth plausibile");
    CHECK([e amplitude] > 0.5, "barra ampiezza con perfusione piena");
    {   // fibrillazione atriale: irregolare ma senza serie, frequenza media rispettata, onda legata al riempimento
        OxiPatient *af = [OxiPatient patientFromState:state(@{ @"rhythm": @"afib", @"pulse_rate_bpm": @90 })];
        OxiEngine *fe = [[OxiEngine alloc] initWithSeed:11]; [fe updateWithPatient:af signal:OxiSignalOK];
        NSMutableArray *bt = [NSMutableArray array]; NSTimeInterval lb = -1;
        NSMutableArray *peaks = [NSMutableArray array]; double pk = 0;
        for (double t = 0; t < 400; t += 0.005) {
            double v = [fe plethAt:t]; NSTimeInterval b = [fe lastPerfusedBeatAtOrBefore:t];
            if (b > lb + 0.05) { if (lb >= 0) [peaks addObject:@(pk)]; [bt addObject:@(b)]; lb = b; pk = 0; }
            pk = MAX(pk, v);
        }
        NSUInteger n = bt.count - 1; double sum = 0, sq = 0; int run = 0, maxRun = 0, prevSign = 0;
        double *rr = calloc(n, sizeof(double));
        for (NSUInteger i = 0; i < n; i++) { rr[i] = [bt[i + 1] doubleValue] - [bt[i] doubleValue]; sum += rr[i]; }
        double mean = sum / n;
        for (NSUInteger i = 0; i < n; i++) {
            sq += (rr[i] - mean) * (rr[i] - mean);
            int sg = rr[i] > mean * 1.04 ? 1 : (rr[i] < mean * 0.96 ? -1 : 0);
            if (sg && sg == prevSign) run++; else run = 1;
            prevSign = sg; if (sg) maxRun = MAX(maxRun, run);
        }
        double cv = sqrt(sq / n) / mean, hr = 60.0 / mean;
        CHECK(hr > 84 && hr < 96, "FA: frequenza media vicina a 90");
        CHECK(cv > 0.10 && cv < 0.25, "FA: variabilità degli intervalli 10-25 %");
        CHECK(maxRun <= 4, "FA: nessuna serie di più di 4 battiti tutti rapidi o tutti lenti");
        double shortAmp = 0, longAmp = 0; int ns = 0, nl = 0;   // picco del battito i+1 dopo l'intervallo rr[i]
        for (NSUInteger i = 0; i + 1 < peaks.count && i < n; i++) {
            if (rr[i] < mean * 0.85) { shortAmp += [peaks[i + 1] doubleValue]; ns++; }
            if (rr[i] > mean * 1.10) { longAmp += [peaks[i + 1] doubleValue]; nl++; }
        }
        CHECK(ns > 10 && nl > 10 && shortAmp / ns < 0.85 * (longAmp / nl), "FA: onda più piccola dopo un intervallo corto");
        free(rr);
    }
    OxiPatient *np = [OxiPatient patientFromState:state(@{ @"pulse_present": @NO, @"rhythm": @"vf" })];
    [e updateWithPatient:np signal:OxiSignalNoPulse];
    double flat = 0; for (double t = 31; t < 35; t += 0.01) flat = MAX(flat, [e plethAt:t]);
    CHECK(flat == 0, "senza polso: linea piatta");
    CHECK([e lastPerfusedBeatAtOrBefore:35] < 31, "senza polso: nessun nuovo battito");
    OxiPatient *lp = [OxiPatient patientFromState:state(@{ @"systolic_mmhg": @60 })];
    [e updateWithPatient:lp signal:OxiSignalOK];
    double m2 = 0; for (double t = 36; t < 42; t += 0.01) m2 = MAX(m2, [e plethAt:t]);
    CHECK(m2 < mx * 0.6, "ipotensione: onda piccola");

    // --- stato locale (uso autonomo) ---
    __block NSTimeInterval T = 1000;
    OxiLocalState *L = [OxiLocalState new]; L.clock = ^NSTimeInterval { return T; };
    NSDictionary *d0 = [L stateDictionary];
    CHECK(([d0[@"spo2_percent"] integerValue] == 97 && [d0[@"pulse_rate_bpm"] integerValue] == 78 && ![d0[@"oximeter"][@"power"] boolValue]), "stato locale iniziale: sano, spento");
    OxiPatient *lp0 = [OxiPatient patientFromState:d0];
    CHECK((lp0 && OxiSignalFor(lp0) == OxiSignalSensorOff), "lo stato locale si legge come quello del monitor (sensore staccato)");
    NSString *err = nil;
    CHECK((![L applyCommand:@{ @"command": @"boh" } error:&err] && err.length), "comando sconosciuto rifiutato");
    CHECK(([L applyCommand:@{ @"command": @"set_sensor", @"value": @{ @"sensor": @"oxi", @"connected": @YES, @"site": @"finger_r2" } } error:&err]), "sensore applicato");
    CHECK((![L applyCommand:@{ @"command": @"set_sensor", @"value": @{ @"sensor": @"ecg", @"connected": @YES } } error:&err]), "solo il sensore oxi");
    T = 1012;
    NSDictionary *d1 = [L stateDictionary];
    CHECK(([d1[@"oximeter"][@"sensor_since_s"] integerValue] == 12 && [d1[@"oximeter"][@"site"] isEqualToString:@"finger_r2"]), "sensor_since conta dal collegamento");
    CHECK(([L applyCommand:@{ @"command": @"transition", @"value": @{ @"params": @{ @"spo2_percent": @87, @"pulse_rate_bpm": @118 }, @"duration_s": @20 } } error:&err]), "transizione accettata");
    T = 1022;
    NSDictionary *d2 = [L stateDictionary];
    CHECK(([d2[@"spo2_percent"] integerValue] == 92 && [d2[@"pulse_rate_bpm"] integerValue] == 98), "a meta' transizione: valori intermedi");
    CHECK(([d2[@"targets"][@"spo2_percent"] integerValue] == 87 && [d2[@"targets"][@"remaining_s"] integerValue] == 10), "obiettivi e tempo residuo");
    CHECK(([L applyCommand:@{ @"command": @"set_simulation_running", @"value": @NO } error:&err]), "pausa");
    T = 1030; NSDictionary *d3 = [L stateDictionary]; T = 1040;
    CHECK(([[L stateDictionary][@"spo2_percent"] integerValue] == [d3[@"spo2_percent"] integerValue]), "in pausa i valori restano fermi");
    [L applyCommand:@{ @"command": @"set_simulation_running", @"value": @YES } error:&err];
    T = 1052;
    CHECK(([[L stateDictionary][@"spo2_percent"] integerValue] == 87), "dopo la pausa la transizione si completa");
    CHECK((![L applyCommand:@{ @"command": @"transition", @"value": @{ @"params": @{ @"etco2_mmhg": @30 } } } error:&err]), "parametro non supportato rifiutato");
    CHECK(([L applyCommand:@{ @"command": @"set_oximeter", @"value": @{ @"power": @YES, @"volume": @40, @"mute_s": @120, @"alarm_limits": @{ @"spo2_low": @90 } } } error:&err]), "set_oximeter completo");
    NSDictionary *d4 = [L stateDictionary];
    CHECK(([d4[@"oximeter"][@"power"] boolValue] && [d4[@"oximeter"][@"volume"] integerValue] == 40 && [d4[@"oximeter"][@"muted_remaining_s"] integerValue] == 120 && [d4[@"oximeter"][@"alarm_limits"][@"spo2_low"] integerValue] == 90), "set_oximeter applicato");
    CHECK((![L applyCommand:@{ @"command": @"set_oximeter", @"value": @{ @"alarm_limits": @{ @"pr_low": @180 } } } error:&err]), "limite basso >= alto rifiutato");
    CHECK([[L stateDictionary][@"oximeter"][@"acquire_s"] integerValue] == 0, "tempo di rilevamento predefinito automatico");
    CHECK(([L applyCommand:@{ @"command": @"set_oximeter", @"value": @{ @"acquire_s": @20 } } error:&err]), "tempo di rilevamento 20 s accettato");
    CHECK([OxiPatient patientFromState:[L stateDictionary]].acquireSec == 20, "tempo di rilevamento letto dal paziente");
    CHECK((![L applyCommand:@{ @"command": @"set_oximeter", @"value": @{ @"acquire_s": @61 } } error:&err]), "tempo di rilevamento oltre 60 s rifiutato");
    [L applyCommand:@{ @"command": @"set_oximeter", @"value": @{ @"acquire_s": @0 } } error:&err];
    CHECK(([L applyCommand:@{ @"command": @"set_pulse_present", @"value": @NO } error:&err] && OxiSignalFor([OxiPatient patientFromState:[L stateDictionary]]) == OxiSignalNoPulse), "polso assente -> nessun polso");
    CHECK(([L applyCommand:@{ @"command": @"set_patient_motion", @"value": @{ @"motion": @"light", @"duration_s": @30 } } error:&err] && [[L stateDictionary][@"patient_motion"] isEqualToString:@"light"]), "movimento");
    T = 1090; CHECK([[L stateDictionary][@"patient_motion"] isEqualToString:@"off"], "movimento scaduto");
    CHECK(([L applyCommand:@{ @"command": @"set_rhythm", @"value": @"afib" } error:&err] && ![L applyCommand:@{ @"command": @"set_rhythm", @"value": @"vt" } error:&err]), "ritmo sinus/afib");
    NSUInteger rev = L.revision;
    CHECK(([L applyCommand:@{ @"command": @"reset_scenario" } error:&err] && L.revision > rev), "reset incrementa la revisione");
    NSDictionary *d5 = [L stateDictionary];
    CHECK((![d5[@"oximeter"][@"power"] boolValue] && ![d5[@"oximeter"][@"sensor_connected"] boolValue] && [d5[@"spo2_percent"] integerValue] == 97 && [d5[@"pulse_present"] boolValue]), "reset: spento, sensore staccato, paziente iniziale");
    CHECK(([NSJSONSerialization isValidJSONObject:d5]), "lo stato locale e' serializzabile in JSON");

    // --- server interno: PIN, blocco, 409 quando collegato ---
    OxiServer *S = [[OxiServer alloc] initWithState:L files:@{ @"index.html": [@"<html>ok</html>" dataUsingEncoding:NSUTF8StringEncoding] }];
    S.pin = @"123456"; S.clock = ^NSTimeInterval { return T; };
    SLHTTPRequest *(^req)(NSString *, NSString *, NSString *, NSString *) = ^SLHTTPRequest *(NSString *m, NSString *path, NSString *tok, NSString *body) {
        SLHTTPRequest *r = [SLHTTPRequest new]; r.method = m; r.path = path; r.remoteAddress = @"10.0.0.2";
        NSMutableDictionary *h = [NSMutableDictionary dictionary]; if (tok) h[@"x-simulafranz-token"] = tok;
        if (body) { h[@"content-type"] = @"application/json"; r.body = [body dataUsingEncoding:NSUTF8StringEncoding]; }
        r.headers = h; return r; };
    CHECK(([S handle:req(@"GET", @"/", nil, nil)].status == 200), "console senza PIN");
    CHECK(([S handle:req(@"GET", @"/api/v1/health", nil, nil)].status == 200), "health senza PIN");
    CHECK(([S handle:req(@"GET", @"/api/v1/state", nil, nil)].status == 401), "stato senza PIN -> 401");
    CHECK(([S handle:req(@"GET", @"/api/v1/state", @"000000", nil)].status == 401), "PIN sbagliato -> 401");
    CHECK(([S handle:req(@"GET", @"/api/v1/state", @"123456", nil)].status == 200), "PIN giusto -> 200");
    CHECK(S.pairedAt == 0, "nessun abbinamento da QR senza header");
    { SLHTTPRequest *pr = req(@"GET", @"/api/v1/state", @"123456", nil); NSMutableDictionary *h = [pr.headers mutableCopy]; h[@"x-simulafranz-pair"] = @"1"; pr.headers = h;
      CHECK(([S handle:pr].status == 200 && S.pairedAt > 0), "console aperta dal QR -> abbinamento registrato");
      SLHTTPRequest *bad = req(@"GET", @"/api/v1/state", @"000000", nil); h = [bad.headers mutableCopy]; h[@"x-simulafranz-pair"] = @"1"; bad.headers = h;
      NSTimeInterval before = S.pairedAt; [S handle:bad]; CHECK(S.pairedAt == before, "abbinamento ignorato con PIN sbagliato"); }
    CHECK(([S handle:req(@"POST", @"/api/v1/command", @"123456", @"{\"command\":\"set_spo2\",\"value\":88}")].status == 200 && [[L stateDictionary][@"spo2_percent"] integerValue] == 88), "comando via API");
    CHECK(([S handle:req(@"POST", @"/api/v1/command", @"123456", @"{\"command\":\"set_spo2\",\"value\":1000}")].status == 400), "comando non valido -> 400");
    CHECK(([S handle:req(@"GET", @"/api/v1/command", @"123456", nil)].status == 405), "metodo sbagliato -> 405");
    CHECK(([S handle:req(@"GET", @"/x", nil, nil)].status == 404), "404");
    S.monitorURL = @"http://192.168.0.10:8080/";
    SLHTTPResponse *r409 = [S handle:req(@"GET", @"/api/v1/state", @"123456", nil)];
    NSDictionary *j409 = [NSJSONSerialization JSONObjectWithData:r409.body options:0 error:NULL];
    CHECK((r409.status == 409 && [j409[@"monitor_url"] isEqualToString:@"http://192.168.0.10:8080/"]), "collegato al monitor -> 409 con indirizzo del monitor");
    S.monitorURL = nil;
    for (int i = 0; i < 5; i++) [S handle:req(@"GET", @"/api/v1/state", @"bad", nil)];
    CHECK(([S handle:req(@"GET", @"/api/v1/state", @"123456", nil)].status == 429), "5 PIN sbagliati -> blocco 429");
    T += 31;
    CHECK(([S handle:req(@"GET", @"/api/v1/state", @"123456", nil)].status == 200), "blocco scaduto dopo 30 s");


    // --- aggiornamenti dal telefono: controllo del pacchetto e API ---
    NSString *okCtl = @"Package: it.simulafranz.saturimetro\nVersion: 0.4.0\nArchitecture: iphoneos-arm\nDescription: prova\n";
    NSString *ue = nil;
    NSDictionary *fields = [OxiUpdate inspectDeb:TestDeb(okCtl) error:&ue];
    CHECK(([fields[@"Version"] isEqualToString:@"0.4.0"]), "aggiornamento: pacchetto valido letto");
    CHECK(([OxiUpdate inspectDeb:TestDeb([okCtl stringByReplacingOccurrencesOfString:@"saturimetro\n" withString:@"monitor\n"]) error:&ue] == nil && [ue containsString:@"non è il saturimetro"]), "aggiornamento: pacchetto di un'altra app rifiutato");
    CHECK(([OxiUpdate inspectDeb:TestDeb([okCtl stringByReplacingOccurrencesOfString:@"iphoneos-arm" withString:@"amd64"]) error:&ue] == nil), "aggiornamento: architettura sbagliata rifiutata");
    CHECK(([OxiUpdate inspectDeb:[@"ciao" dataUsingEncoding:NSUTF8StringEncoding] error:&ue] == nil && [ue containsString:@".deb"]), "aggiornamento: file qualsiasi rifiutato");
    NSMutableData *rotto = [TestDeb(okCtl) mutableCopy]; ((char *)rotto.mutableBytes)[rotto.length - 20] ^= 0x55;
    CHECK(([OxiUpdate inspectDeb:rotto error:&ue] == nil), "aggiornamento: pacchetto danneggiato rifiutato");
    CHECK(([OxiUpdate compareVersion:@"0.3.10" to:@"0.3.9"] == NSOrderedDescending && [OxiUpdate compareVersion:@"0.4" to:@"0.4.0"] == NSOrderedSame
           && [OxiUpdate compareVersion:@"0.3.1" to:@"1.0.0"] == NSOrderedAscending), "aggiornamento: confronto delle versioni");
    NSString *realDeb = [[NSProcessInfo processInfo] environment][@"TEST_DEB"];
    if (realDeb.length) { NSDictionary *rf = [OxiUpdate inspectDeb:[NSData dataWithContentsOfFile:realDeb] error:&ue];
        CHECK(([rf[@"Package"] isEqualToString:@"it.simulafranz.saturimetro"]), "aggiornamento: il .deb vero dell'app viene accettato"); }
    __block NSData *installed = nil;
    S.installHandler = ^NSString *(NSData *deb, NSString **err) { NSDictionary *f = [OxiUpdate inspectDeb:deb error:err]; if (f) installed = deb; return f[@"Version"]; };
    T += 100;
    CHECK(([S handle:req(@"GET", @"/api/v1/update", nil, nil)].status == 401), "aggiornamento: senza PIN -> 401");
    SLHTTPResponse *ur = [S handle:req(@"GET", @"/api/v1/update", @"123456", nil)];
    NSDictionary *uj = [NSJSONSerialization JSONObjectWithData:ur.body options:0 error:NULL];
    CHECK((ur.status == 200 && uj[@"version"] && [uj[@"package"] isEqualToString:@"it.simulafranz.saturimetro"] && uj[@"installer"]), "aggiornamento: GET versione e stato dell'installatore");
    SLHTTPRequest *up = req(@"POST", @"/api/v1/update", @"123456", nil); up.body = TestDeb(okCtl);
    SLHTTPResponse *ur2 = [S handle:up];
    CHECK((ur2.status == 202 && installed.length > 0), "aggiornamento: pacchetto valido accettato (202)");
    installed = nil; up.body = [@"non sono un deb" dataUsingEncoding:NSUTF8StringEncoding];
    CHECK(([S handle:up].status == 400 && installed == nil), "aggiornamento: pacchetto non valido -> 400, nulla installato");
    S.monitorURL = @"http://192.168.0.10:8080/"; up.body = TestDeb(okCtl);
    CHECK(([S handle:up].status == 202), "aggiornamento: possibile anche quando l'iPod è collegato al monitor");
    S.monitorURL = nil;
    printf("Test superati: %d   falliti: %d\n", passed, failed);
    return failed ? 1 : 0;
} }
