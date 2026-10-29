//
//  clipboard_protocol_tests.m
//  Exercises the CLIPRDR controller with a fake channel interface. This is a
//  protocol/unit test, not a substitute for a real Windows session.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "RDPMacInternal.h"

static int gFailures = 0;
static int gCapabilitiesCalls = 0;
static int gFormatListCalls = 0;
static int gFormatListResponseCalls = 0;
static int gDataRequestCalls = 0;
static int gDataResponseCalls = 0;
static uint32_t gLastAdvertisedFormat = 0;
static uint32_t gLastRequestedFormat = 0;
static uint16_t gLastResponseFlags = 0;
static NSData *gLastResponseData = nil;

static void expect(BOOL condition, NSString *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        gFailures++;
    } else {
        printf("ok: %s\n", message.UTF8String);
    }
}

static void expectEqualStrings(NSString *actual, NSString *expected, NSString *message)
{
    if (![actual isEqualToString:expected]) {
        fprintf(stderr, "FAIL: %s (got %s, expected %s)\n", message.UTF8String,
                actual.UTF8String ?: "(nil)", expected.UTF8String ?: "(nil)");
        gFailures++;
    } else {
        printf("ok: %s\n", message.UTF8String);
    }
}

static UINT fake_caps(CliprdrClientContext *clip, const CLIPRDR_CAPABILITIES *caps)
{
    (void)clip;
    (void)caps;
    gCapabilitiesCalls++;
    return CHANNEL_RC_OK;
}

static UINT fake_format_list(CliprdrClientContext *clip, const CLIPRDR_FORMAT_LIST *list)
{
    (void)clip;
    gFormatListCalls++;
    if (list && list->numFormats > 0)
        gLastAdvertisedFormat = list->formats[0].formatId;
    return CHANNEL_RC_OK;
}

static UINT fake_format_list_response(CliprdrClientContext *clip,
                                       const CLIPRDR_FORMAT_LIST_RESPONSE *response)
{
    (void)clip;
    (void)response;
    gFormatListResponseCalls++;
    return CHANNEL_RC_OK;
}

static UINT fake_data_request(CliprdrClientContext *clip,
                              const CLIPRDR_FORMAT_DATA_REQUEST *request)
{
    (void)clip;
    gDataRequestCalls++;
    if (request)
        gLastRequestedFormat = request->requestedFormatId;
    return CHANNEL_RC_OK;
}

static UINT fake_data_response(CliprdrClientContext *clip,
                               const CLIPRDR_FORMAT_DATA_RESPONSE *response)
{
    (void)clip;
    gDataResponseCalls++;
    if (!response)
        return CHANNEL_RC_OK;
    gLastResponseFlags = response->common.msgFlags;
    if (response->requestedFormatData && response->common.dataLen > 0) {
        gLastResponseData = [NSData dataWithBytes:response->requestedFormatData
                                           length:response->common.dataLen];
    } else {
        gLastResponseData = [NSData data];
    }
    return CHANNEL_RC_OK;
}

int main(void)
{
    @autoreleasepool {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        NSMutableArray<NSPasteboardItem *> *savedItems = [NSMutableArray array];
        for (NSPasteboardItem *item in [pasteboard pasteboardItems]) {
            NSPasteboardItem *copy = [NSPasteboardItem new];
            for (NSPasteboardType type in item.types) {
                NSData *data = [item dataForType:type];
                if (data)
                    [copy setData:data forType:type];
            }
            [savedItems addObject:copy];
        }

        CliprdrClientContext clip = {0};
        clip.ClientCapabilities = fake_caps;
        clip.ClientFormatList = fake_format_list;
        clip.ClientFormatListResponse = fake_format_list_response;
        clip.ClientFormatDataRequest = fake_data_request;
        clip.ClientFormatDataResponse = fake_data_response;

        [pasteboard clearContents];
        [pasteboard setString:@"Исходный текст Mac" forType:NSPasteboardTypeString];

        RDPMacClipboardController *controller =
            [[RDPMacClipboardController alloc] initWithEnabled:YES];
        [controller attachChannel:&clip];
        [controller handleMonitorReady];

        expect(gCapabilitiesCalls == 1, @"MonitorReady sends capabilities");
        expect(gFormatListCalls >= 1, @"MonitorReady advertises local clipboard");
        expect(gLastAdvertisedFormat == 13, @"local format is CF_UNICODETEXT");

        [controller handleServerFormatListIds:@[ @13 ] names:@[ @"CF_UNICODETEXT" ]];
        expect(gFormatListResponseCalls == 1, @"remote format list is acknowledged");
        expect(gDataRequestCalls == 1, @"remote format list triggers data request");
        expect(gLastRequestedFormat == 13, @"requested CF_UNICODETEXT");

        RDPMacClipboardDiagnostics *pending = [controller diagnostics];
        expect(pending.pendingRequest != nil, @"diagnostics show a pending request");

        NSString *remoteText = @"Windows → Mac\nВторая строка\nEmoji 🚀";
        NSData *remoteData = RDPMacClipboardEncodeText(remoteText, 13, NULL);
        [controller handleServerFormatDataResponse:remoteData flags:CB_RESPONSE_OK];

        expect([[pasteboard stringForType:NSPasteboardTypeString] isEqualToString:remoteText],
               @"remote text is written to the macOS pasteboard");
        RDPMacClipboardDiagnostics *afterReceive = [controller diagnostics];
        expect(afterReceive.receiveCount == 1, @"receive counter incremented");
        expect(afterReceive.pendingRequest == nil, @"pending request cleared");
        expect(gFormatListCalls == 1, @"no echo format list after applying remote text");

        const int listsBeforeRequest = gFormatListCalls;
        [controller handleServerFormatDataRequestFormat:13];
        expect(gDataResponseCalls == 1, @"remote data request answered");
        expect(gLastResponseFlags == CB_RESPONSE_OK, @"data response flags OK");
        expectEqualStrings(RDPMacClipboardDecodeText(gLastResponseData, 13), remoteText,
                           @"data response contains current pasteboard text");
        expect(gFormatListCalls == listsBeforeRequest, @"answering does not advertise formats");

        NSString *localText = @"Новый локальный текст: привет";
        [pasteboard clearContents];
        [pasteboard setString:localText forType:NSPasteboardTypeString];
        [controller sendLocalClipboard];
        expect(gFormatListCalls == listsBeforeRequest + 1, @"manual send advertises formats");

        [controller handleServerFormatDataRequestFormat:13];
        expectEqualStrings(RDPMacClipboardDecodeText(gLastResponseData, 13), localText,
                           @"manual send returns the new local text");

        // Echo of our own text must not rewrite the pasteboard or start a loop.
        const int listsBeforeEcho = gFormatListCalls;
        [controller handleServerFormatDataResponse:RDPMacClipboardEncodeText(localText, 13, NULL)
                                            flags:CB_RESPONSE_OK];
        expectEqualStrings([pasteboard stringForType:NSPasteboardTypeString], localText,
                           @"echo keeps pasteboard unchanged");
        expect(gFormatListCalls == listsBeforeEcho, @"echo does not advertise formats again");

        [controller handleServerFormatDataResponse:[NSData data] flags:CB_RESPONSE_FAIL];
        RDPMacClipboardDiagnostics *afterFailure = [controller diagnostics];
        expect(afterFailure.failureCount > 0, @"failure counter incremented");
        expect(afterFailure.lastError.length > 0, @"failure recorded in diagnostics");

        NSString *secret = @"СЕКРЕТНОЕ-СОДЕРЖИМОЕ-123";
        [pasteboard clearContents];
        [pasteboard setString:secret forType:NSPasteboardTypeString];
        [controller sendLocalClipboard];
        NSString *report = [controller diagnosticsReport];
        expect([report rangeOfString:secret].location == NSNotFound,
               @"diagnostics report does not contain clipboard contents");
        expect([report containsString:@"CF_UNICODETEXT"], @"report lists formats");
        expect([report containsString:@"Содержимое буфера"], @"report states no content is logged");

        [controller handleChannelDisconnected];
        expect([controller diagnostics].channelConnected == NO, @"channel disconnect updates state");
        [controller shutdown];

        [pasteboard clearContents];
        if (savedItems.count > 0)
            [pasteboard writeObjects:savedItems];

        if (gFailures == 0) {
            printf("RESULT: OK\n");
            return 0;
        }
        printf("RESULT: %d FAILURES\n", gFailures);
        return 1;
    }
}
