// Server di riferimento su Mac del saturimetro in uso autonomo (stessa API/console dell'iPod), per provare la
// console web con un browser senza l'iPod:  mac-oxi-server <porta> <PIN> <cartella www>
#import <Foundation/Foundation.h>
#import "OxiLocalState.h"
#import "OxiServer.h"
int main(int argc, char **argv) { @autoreleasepool {
    if (argc < 4) { fprintf(stderr, "uso: mac-oxi-server <porta> <PIN> <cartella www>\n"); return 2; }
    NSData *html = [NSData dataWithContentsOfFile:[@(argv[3]) stringByAppendingPathComponent:@"index.html"]];
    if (!html) { fprintf(stderr, "index.html mancante in %s\n", argv[3]); return 2; }
    OxiServer *s = [[OxiServer alloc] initWithState:[OxiLocalState new] files:@{ @"index.html": html }];
    s.pin = @(argv[2]); s.bonjour = NO;
    NSError *err = nil;
    if (![s startOnPort:(uint16_t)atoi(argv[1]) error:&err]) { fprintf(stderr, "avvio fallito: %s\n", err.localizedDescription.UTF8String); return 1; }
    printf("similFranzSat (riferimento Mac) su http://127.0.0.1:%s/  PIN %s\n", argv[1], argv[2]); fflush(stdout);
    [[NSRunLoop mainRunLoop] run];
    return 0;
} }
