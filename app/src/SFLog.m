#import "SFLog.h"

void SFLog(NSString *format, ...) {
    va_list ap; va_start(ap, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    NSLog(@"[SimulaFranz_Saturimetro] %@", msg);
    static NSString *path; static NSDateFormatter *fmt; static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
        path = [dir stringByAppendingPathComponent:@"SimulaFranz_Saturimetro.log"];
        fmt = [NSDateFormatter new]; fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        q = dispatch_queue_create("it.simulafranz.saturimetro.log", DISPATCH_QUEUE_SERIAL);
    });
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [fmt stringFromDate:[NSDate date]], msg];
    dispatch_async(q, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDictionary *a = [fm attributesOfItemAtPath:path error:NULL];
        if (a && [a fileSize] > 256 * 1024) {
            [fm removeItemAtPath:[path stringByAppendingString:@".1"] error:NULL];
            [fm moveItemAtPath:path toPath:[path stringByAppendingString:@".1"] error:NULL];
        }
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    });
}
