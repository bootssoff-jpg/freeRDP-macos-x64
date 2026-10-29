#import "RDPMacClipboardText.h"

const uint32_t RDPMacClipboardFormatUnicodeText = 13;
const uint32_t RDPMacClipboardFormatText = 1;

NSString *RDPMacClipboardFormatName(uint32_t formatId)
{
    switch (formatId) {
        case 1:
            return @"CF_TEXT";
        case 2:
            return @"CF_BITMAP";
        case 8:
            return @"CF_DIB";
        case 13:
            return @"CF_UNICODETEXT";
        case 15:
            return @"CF_HDROP";
        case 16:
            return @"CF_LOCALE";
        case 17:
            return @"CF_DIBV5";
        case 49161:
            return @"HTML Format";
        case 49324:
            return @"PNG";
        default:
            return [NSString stringWithFormat:@"format #%u", formatId];
    }
}

static NSStringEncoding RDPMacCyrillicEncoding(void)
{
    // Windows-1251, the default ANSI code page on most Russian Windows installs.
    CFStringEncoding cf = CFStringConvertWindowsCodepageToEncoding(1251);
    if (cf == kCFStringEncodingInvalidId)
        return NSWindowsCP1251StringEncoding;
    return CFStringConvertEncodingToNSStringEncoding(cf);
}

static NSStringEncoding RDPMacWesternEncoding(void)
{
    CFStringEncoding cf = CFStringConvertWindowsCodepageToEncoding(1252);
    if (cf == kCFStringEncodingInvalidId)
        return NSWindowsCP1252StringEncoding;
    return CFStringConvertEncodingToNSStringEncoding(cf);
}

static BOOL RDPMacClipboardIsAscii(NSString *text)
{
    const NSUInteger length = text.length;
    for (NSUInteger i = 0; i < length; i++) {
        if ([text characterAtIndex:i] > 0x7F)
            return NO;
    }
    return YES;
}

BOOL RDPMacClipboardCanEncodeText(NSString *text, uint32_t formatId)
{
    if (text.length == 0)
        return YES;
    if (formatId == RDPMacClipboardFormatUnicodeText)
        return YES;
    if (formatId != RDPMacClipboardFormatText)
        return NO;
    if (RDPMacClipboardIsAscii(text))
        return YES;
    return [text canBeConvertedToEncoding:RDPMacCyrillicEncoding()] ||
           [text canBeConvertedToEncoding:RDPMacWesternEncoding()];
}

NSData *RDPMacClipboardEncodeText(NSString *text, uint32_t formatId, NSError **error)
{
    if (!RDPMacClipboardCanEncodeText(text, formatId)) {
        if (error) {
            *error = [NSError errorWithDomain:@"RDPMacClipboard"
                                         code:2
                                     userInfo:@{
                                         NSLocalizedDescriptionKey :
                                             @"Текст содержит символы, которые нельзя передать в этом формате"
                                     }];
        }
        return nil;
    }

    if (formatId == RDPMacClipboardFormatUnicodeText) {
        NSMutableData *out = [[text dataUsingEncoding:NSUTF16LittleEndianStringEncoding
                                allowLossyConversion:NO] mutableCopy];
        if (!out) {
            if (error) {
                *error = [NSError errorWithDomain:@"RDPMacClipboard"
                                             code:5
                                         userInfo:@{
                                             NSLocalizedDescriptionKey :
                                                 @"Не удалось закодировать Unicode-текст"
                                         }];
            }
            return nil;
        }
        uint8_t nul[2] = {0, 0};
        [out appendBytes:nul length:2];
        return out;
    }

    if (formatId == RDPMacClipboardFormatText) {
        NSStringEncoding encoding = RDPMacClipboardIsAscii(text) ? NSASCIIStringEncoding
                                                                 : RDPMacCyrillicEncoding();
        NSMutableData *data = [[text dataUsingEncoding:encoding allowLossyConversion:NO] mutableCopy];
        if (!data) {
            encoding = RDPMacWesternEncoding();
            data = [[text dataUsingEncoding:encoding allowLossyConversion:NO] mutableCopy];
        }
        if (!data) {
            if (error) {
                *error = [NSError errorWithDomain:@"RDPMacClipboard"
                                             code:3
                                         userInfo:@{
                                             NSLocalizedDescriptionKey :
                                                 @"Не удалось закодировать текст в CF_TEXT"
                                         }];
            }
            return nil;
        }
        uint8_t nul = 0;
        [data appendBytes:&nul length:1];
        return data;
    }

    if (error) {
        *error = [NSError errorWithDomain:@"RDPMacClipboard"
                                     code:4
                                 userInfo:@{
                                     NSLocalizedDescriptionKey :
                                         @"Формат буфера обмена не поддерживается"
                                 }];
    }
    return nil;
}

static NSString *RDPMacDecodeUnicodeText(NSData *data)
{
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    if (length == 0)
        return @"";
    if (length % 2 != 0)
        length -= 1;
    // Tolerate a UTF-16LE BOM even though CF_UNICODETEXT normally has none.
    if (length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        bytes += 2;
        length -= 2;
    }

    // Stop at the first UTF-16 NUL; Windows includes a terminator.
    NSUInteger textBytes = length;
    for (NSUInteger i = 0; i + 1 < length; i += 2) {
        if (bytes[i] == 0 && bytes[i + 1] == 0) {
            textBytes = i;
            break;
        }
    }
    if (textBytes == 0)
        return @"";

    return [[NSString alloc] initWithBytes:bytes
                                    length:textBytes
                                  encoding:NSUTF16LittleEndianStringEncoding];
}

static NSString *RDPMacDecodeAnsiText(NSData *data)
{
    if (data.length == 0)
        return @"";
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    for (NSUInteger i = 0; i < length; i++) {
        if (bytes[i] == 0) {
            length = i;
            break;
        }
    }
    if (length == 0)
        return @"";
    NSData *payload = [data subdataWithRange:NSMakeRange(0, length)];

    // Some Windows applications put UTF-8 into CF_TEXT. Prefer a strict
    // UTF-8 decode when it produces non-ASCII text; otherwise use the ANSI
    // code pages that are realistic for Russian/European servers.
    NSString *utf8 = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
    if (utf8 && ![utf8 canBeConvertedToEncoding:NSASCIIStringEncoding])
        return utf8;

    NSString *cyrillic = [[NSString alloc] initWithData:payload encoding:RDPMacCyrillicEncoding()];
    NSString *western = [[NSString alloc] initWithData:payload encoding:RDPMacWesternEncoding()];
    if (cyrillic && western && ![cyrillic isEqualToString:western])
        return cyrillic;
    if (western)
        return western;
    return [[NSString alloc] initWithData:payload encoding:NSISOLatin1StringEncoding];
}

NSString *RDPMacClipboardDecodeText(NSData *data, uint32_t formatId)
{
    if (formatId == RDPMacClipboardFormatUnicodeText)
        return RDPMacDecodeUnicodeText(data);
    if (formatId == RDPMacClipboardFormatText)
        return RDPMacDecodeAnsiText(data);
    return nil;
}
