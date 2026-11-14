#import "OxiUpdate.h"
#include <zlib.h>
#include <spawn.h>
#include <sys/stat.h>

NSString *const OxiUpdatePackage = @"it.simulafranz.saturimetro";
NSString *const OxiUpdateDebPath = @"/var/mobile/Library/Caches/similfranz-aggiornamento.deb";
NSString *const OxiUpdateHelperPath = @"/usr/libexec/similfranz-sat-aggiorna";
extern char **environ;

static NSData *Gunzip(NSData *gz) {
    if (gz.length < 18) return nil;
    z_stream z; memset(&z, 0, sizeof z);
    if (inflateInit2(&z, 16 + MAX_WBITS) != Z_OK) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:gz.length * 4 + 1024];
    z.next_in = (Bytef *)gz.bytes; z.avail_in = (uInt)gz.length;
    int r;
    do {
        if (z.total_out >= out.length) {
            if (out.length > 16 * 1024 * 1024) { inflateEnd(&z); return nil; }   // control.tar non può essere così grande
            out.length *= 2;
        }
        z.next_out = (Bytef *)out.mutableBytes + z.total_out; z.avail_out = (uInt)(out.length - z.total_out);
        r = inflate(&z, Z_NO_FLUSH);
    } while (r == Z_OK);
    inflateEnd(&z);
    if (r != Z_STREAM_END) return nil;
    out.length = z.total_out;
    return out;
}

// Archivio "ar" del .deb -> contenuto del membro il cui nome inizia con prefix
static NSData *ArMember(NSData *deb, NSString *prefix) {
    const char *b = deb.bytes; NSUInteger n = deb.length, pos = 8;
    if (n < 8 || memcmp(b, "!<arch>\n", 8) != 0) return nil;
    while (pos + 60 <= n) {
        NSString *name = [[[NSString alloc] initWithBytes:b + pos length:16 encoding:NSASCIIStringEncoding]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *sz = [[NSString alloc] initWithBytes:b + pos + 48 length:10 encoding:NSASCIIStringEncoding];
        long long size = [[sz stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] longLongValue];
        if (size < 0 || pos + 60 + (NSUInteger)size > n) return nil;
        if ([name hasPrefix:prefix]) return [deb subdataWithRange:NSMakeRange(pos + 60, (NSUInteger)size)];
        pos += 60 + (NSUInteger)size + ((NSUInteger)size % 2);
    }
    return nil;
}

// Archivio tar (USTAR) -> contenuto del file "control"
static NSData *TarControl(NSData *tar) {
    const char *b = tar.bytes; NSUInteger n = tar.length, pos = 0;
    while (pos + 512 <= n) {
        if (b[pos] == 0) break;
        NSString *name = [[NSString alloc] initWithBytes:b + pos length:strnlen(b + pos, 100) encoding:NSUTF8StringEncoding] ?: @"";
        char szs[13] = {0}; memcpy(szs, b + pos + 124, 12);
        unsigned long long size = strtoull(szs, NULL, 8);
        if (pos + 512 + size > n) return nil;
        if ([name isEqualToString:@"./control"] || [name isEqualToString:@"control"])
            return [tar subdataWithRange:NSMakeRange(pos + 512, (NSUInteger)size)];
        pos += 512 + (NSUInteger)((size + 511) / 512 * 512);
    }
    return nil;
}

@implementation OxiUpdate

+ (NSDictionary<NSString *, NSString *> *)inspectDeb:(NSData *)deb error:(NSString **)error {
    NSData *ctlGz = deb.length ? ArMember(deb, @"control.tar.gz") : nil;
    if (!ctlGz) { if (error) *error = @"non è un pacchetto .deb valido (o è compresso in un formato non supportato)"; return nil; }
    NSData *tar = Gunzip(ctlGz), *ctl = tar ? TarControl(tar) : nil;
    NSString *text = ctl ? [[NSString alloc] initWithData:ctl encoding:NSUTF8StringEncoding] : nil;
    if (!text) { if (error) *error = @"pacchetto danneggiato: manca il file control"; return nil; }
    NSMutableDictionary *f = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange r = [line rangeOfString:@": "];
        if (r.location != NSNotFound && ![line hasPrefix:@" "]) f[[line substringToIndex:r.location]] = [line substringFromIndex:r.location + 2];
    }
    if (![f[@"Package"] isEqualToString:OxiUpdatePackage]) {
        if (error) *error = [NSString stringWithFormat:@"questo pacchetto non è il saturimetro (%@)", f[@"Package"] ?: @"senza nome"]; return nil;
    }
    if (![f[@"Architecture"] isEqualToString:@"iphoneos-arm"]) { if (error) *error = @"pacchetto per un'altra architettura"; return nil; }
    if (![f[@"Version"] length] || [f[@"Version"] length] > 32) { if (error) *error = @"pacchetto senza versione"; return nil; }
    return f;
}

+ (BOOL)installerAvailable {
    struct stat st;
    if (stat(OxiUpdateHelperPath.fileSystemRepresentation, &st) != 0) return NO;
    return st.st_uid == 0 && (st.st_mode & S_ISUID) && (st.st_mode & S_IXOTH);
}

+ (NSString *)installDeb:(NSData *)deb error:(NSString **)error {
    NSDictionary *f = [self inspectDeb:deb error:error];
    if (!f) return nil;
    if (![self installerAvailable]) { if (error) *error = @"manca l'aiutante di installazione: aggiorna una volta dal Mac (aggiorna.sh)"; return nil; }
    [[NSFileManager defaultManager] removeItemAtPath:OxiUpdateDebPath error:NULL];
    if (![deb writeToFile:OxiUpdateDebPath atomically:YES]) { if (error) *error = @"impossibile salvare il pacchetto"; return nil; }
    pid_t pid; const char *argv[] = { OxiUpdateHelperPath.fileSystemRepresentation, NULL };
    int rc = posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, environ);
    if (rc != 0) { if (error) *error = [NSString stringWithFormat:@"aiutante non avviato (%d)", rc]; return nil; }
    return f[@"Version"];
}

+ (NSComparisonResult)compareVersion:(NSString *)a to:(NSString *)b {
    NSArray *x = [a componentsSeparatedByString:@"."], *y = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(x.count, y.count); i++) {
        NSInteger p = i < x.count ? [x[i] integerValue] : 0, q = i < y.count ? [y[i] integerValue] : 0;
        if (p != q) return p < q ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}
@end
