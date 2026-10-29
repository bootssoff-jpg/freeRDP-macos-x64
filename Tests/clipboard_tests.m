//
//  clipboard_tests.m
//  Unit tests for CLIPRDR text serialization (no live session required).
//

#import <Foundation/Foundation.h>
#import "RDPMacClipboardText.h"

static int gFailures = 0;

static void expect(BOOL condition, NSString *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        gFailures++;
    } else {
        printf("ok: %s\n", message.UTF8String);
    }
}

static void expectEqual(NSString *actual, NSString *expected, NSString *message)
{
    if (![actual isEqualToString:expected]) {
        fprintf(stderr, "FAIL: %s (got %s, expected %s)\n", message.UTF8String,
                actual.UTF8String ?: "(nil)", expected.UTF8String ?: "(nil)");
        gFailures++;
    } else {
        printf("ok: %s\n", message.UTF8String);
    }
}

int main(void)
{
    @autoreleasepool {
        expectEqual(RDPMacClipboardFormatName(13), @"CF_UNICODETEXT", @"format name 13");
        expectEqual(RDPMacClipboardFormatName(1), @"CF_TEXT", @"format name 1");
        expect([RDPMacClipboardFormatName(49324) containsString:@"PNG"], @"format name PNG");

        NSError *error = nil;
        NSString *samples[] = {
            @"Hello, world!",
            @"Привет, мир!",
            @"Первая строка\nВторая строка\n\nЧетвёртая",
            @"Tab\there; quotes \"'\" and symbols <>&",
            @"Emoji: 🚀😀 и комбинированный: e\u0301",
            @"",
        };
        for (size_t i = 0; i < sizeof(samples) / sizeof(samples[0]); i++) {
            NSData *encoded = RDPMacClipboardEncodeText(samples[i], 13, &error);
            expect(encoded != nil, [NSString stringWithFormat:@"encode UTF-16 sample %zu", i]);
            if (!encoded)
                continue;
            expect(encoded.length >= 2, @"UTF-16 payload has NUL terminator");
            const uint8_t *bytes = encoded.bytes;
            expect(bytes[encoded.length - 2] == 0 && bytes[encoded.length - 1] == 0,
                   @"UTF-16 payload ends with two zero bytes");
            NSString *decoded = RDPMacClipboardDecodeText(encoded, 13);
            expectEqual(decoded, samples[i],
                        [NSString stringWithFormat:@"roundtrip sample %zu", i]);
        }

        // Large multiline text (1 MiB of Cyrillic/Latin).
        NSMutableString *large = [NSMutableString string];
        for (int i = 0; i < 40000; i++) {
            [large appendFormat:@"Строка %d — line %d\n", i, i];
        }
        NSData *largeData = RDPMacClipboardEncodeText(large, 13, &error);
        expect(largeData.length > 1000000, @"large text encodes over 1 MB");
        expectEqual(RDPMacClipboardDecodeText(largeData, 13), large, @"large text roundtrip");

        // UTF-16 without terminator, odd length and embedded NUL.
        uint8_t raw[] = {'A', 0, 'B', 0, 'C', 0};
        NSString *noNul = RDPMacClipboardDecodeText([NSData dataWithBytes:raw length:6], 13);
        expectEqual(noNul, @"ABC", @"decode UTF-16 without terminator");
        NSString *odd = RDPMacClipboardDecodeText([NSData dataWithBytes:raw length:5], 13);
        expectEqual(odd, @"AB", @"decode odd-length UTF-16 (truncated safely)");
        uint8_t withNul[] = {'A', 0, 0, 0, 'B', 0};
        NSString *stopped = RDPMacClipboardDecodeText([NSData dataWithBytes:withNul
                                                                      length:sizeof(withNul)], 13);
        expectEqual(stopped, @"A", @"decode stops at UTF-16 NUL");
        uint8_t bom[] = {0xFF, 0xFE, 'A', 0, 'B', 0, 0, 0};
        expectEqual(RDPMacClipboardDecodeText([NSData dataWithBytes:bom length:sizeof(bom)], 13),
                    @"AB", @"decode strips UTF-16LE BOM");

        // CF_TEXT with Windows-1251.
        NSString *cyrillic = @"Привет из CF_TEXT";
        NSData *ansi = RDPMacClipboardEncodeText(cyrillic, 1, &error);
        expect(ansi != nil, @"encode CF_TEXT CP1251");
        expect(ansi.length == [cyrillic lengthOfBytesUsingEncoding:NSWindowsCP1251StringEncoding] + 1,
               @"CF_TEXT has ANSI terminator");
        expectEqual(RDPMacClipboardDecodeText(ansi, 1), cyrillic, @"CF_TEXT CP1251 roundtrip");

        // CF_TEXT with UTF-8 payload (some applications do this).
        NSData *utf8 = [@"Привет UTF-8" dataUsingEncoding:NSUTF8StringEncoding];
        expectEqual(RDPMacClipboardDecodeText(utf8, 1), @"Привет UTF-8",
                    @"CF_TEXT UTF-8 heuristic");

        // Unsupported format must be rejected without crashing.
        expect(RDPMacClipboardEncodeText(@"x", 8, &error) == nil, @"CF_DIB encode rejected");
        expect(RDPMacClipboardDecodeText([NSData data], 8) == nil, @"CF_DIB decode rejected");

        // NULL/empty input safety.
        expectEqual(RDPMacClipboardDecodeText([NSData data], 13), @"", @"empty UTF-16 data");
        expectEqual(RDPMacClipboardDecodeText([NSData data], 1), @"", @"empty ANSI data");

        if (gFailures == 0) {
            printf("RESULT: OK\n");
            return 0;
        }
        printf("RESULT: %d FAILURES\n", gFailures);
        return 1;
    }
}
