//
//  bridge_lifecycle.m
//  Exercises the real connection lifecycle without a reachable RDP server:
//  argument validation, TCP failure, state propagation, resource release and
//  a second start on the same object.
//

#import <Foundation/Foundation.h>
#import "RDPMacBridge.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <winpr/wlog.h>
extern NSString *RDPMacDiagnosticLogSite(const wLogMessage *message);

@interface RDPMacClient (FrameTest)
- (void)framebufferConfigureWithWidth:(size_t)width height:(size_t)height;
@end

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

static void pumpMainQueue(NSTimeInterval seconds)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
}

static BOOL waitForFailure(RDPMacClient *client, NSTimeInterval timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (client.state == RDPMacConnectionStateConnecting && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
    return client.state == RDPMacConnectionStateFailed && client.lastErrorText.length > 0;
}

static BOOL startToPort(RDPMacClient *client, NSInteger port, NSError **error)
{
    return [client startWithHost:@"127.0.0.1"
                            port:port
                        username:@"test"
                          domain:@""
                        password:@"not-a-real-password"
                           width:800
                          height:600
                    securityMode:RDPMacSecurityModeNegotiate
                clipboardEnabled:YES
                commandAsControl:YES
          allowLegacyTLS:NO
        certificatePromptTimeout:5
                           error:error];
}

static BOOL startToClosedPort(RDPMacClient *client, NSError **error)
{
    return startToPort(client, 1, error);
}

static void testConcurrentConnections(void)
{
    // A loopback listener deliberately leaves RDP negotiation pending. This
    // tests real independent connection threads, not Windows authentication.
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    BOOL ready = listener >= 0 && bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0
                 && listen(listener, 4) == 0;
    expect(ready, @"loopback listener available for concurrent connection test");
    if (!ready) { if (listener >= 0) close(listener); return; }
    socklen_t length = sizeof(address);
    getsockname(listener, (struct sockaddr *)&address, &length);
    RDPMacClient *first = [RDPMacClient new];
    RDPMacClient *second = [RDPMacClient new];
    NSError *error = nil;
    expect(startToPort(first, ntohs(address.sin_port), &error), @"first concurrent connection starts");
    expect(startToPort(second, ntohs(address.sin_port), &error), @"second concurrent connection starts");
    pumpMainQueue(0.5);
    expect(first.state == RDPMacConnectionStateConnecting && second.state == RDPMacConnectionStateConnecting,
           @"two independent RDP handshakes are pending simultaneously");
    [first disconnect];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while ((first.state == RDPMacConnectionStateConnecting || first.state == RDPMacConnectionStateDisconnecting)
           && deadline.timeIntervalSinceNow > 0) pumpMainQueue(0.05);
    expect(first.state == RDPMacConnectionStateFailed || first.state == RDPMacConnectionStateDisconnected,
           @"first concurrent connection cancels cleanly");
    expect(second.state == RDPMacConnectionStateConnecting,
           @"cancelling the first connection does not cancel the second");
    [second disconnect];
    close(listener);
    pumpMainQueue(0.5);
}

int main(void)
{
    @autoreleasepool {
        NSString *selfTest = RDPMacClient.selfTestReport;
        printf("%s", selfTest.UTF8String);
        expect([selfTest hasSuffix:@"RESULT: OK\n"],
               @"self-test completes without a failed subsystem");
        expect([selfTest containsString:@"NTLM NT hash (MD4): OK"],
               @"self-test proves the NTLM/CredSSP MD4 implementation works");
        expect([selfTest containsString:@"RDP standard security cipher (RC4): OK"],
               @"self-test proves the RC4 implementation works");
        wLogMessage diagnostic = {0};
        diagnostic.Type = WLOG_MESSAGE_TEXT;
        diagnostic.Level = WLOG_ERROR;
        diagnostic.FileName = "/private/build/example/transport.c";
        diagnostic.FunctionName = "transport_connect_nla";
        diagnostic.LineNumber = 42;
        diagnostic.TextString = "PRIVATE_PASSWORD_AND_CLIPBOARD_SENTINEL";
        diagnostic.FormatString = diagnostic.TextString;
        diagnostic.PrefixString = (char *)diagnostic.TextString;
        NSString *site = RDPMacDiagnosticLogSite(&diagnostic);
        expect([site containsString:@"transport.c:42 transport_connect_nla"],
               @"diagnostics retain the failing upstream source location");
        expect(![site containsString:@"PRIVATE_"] && ![site containsString:@"/private/"],
               @"diagnostics discard message payloads and absolute source paths");
        diagnostic.Type = WLOG_MESSAGE_DATA;
        expect(RDPMacDiagnosticLogSite(&diagnostic) == nil, @"binary upstream logs are discarded");
        diagnostic.Type = WLOG_MESSAGE_TEXT;
        diagnostic.FunctionName = "invalid function with payload";
        expect(RDPMacDiagnosticLogSite(&diagnostic) == nil, @"unexpected source metadata is discarded");
        testConcurrentConnections();

        {
            RDPMacClient *client = [[RDPMacClient alloc] init];
            NSError *error = nil;
            BOOL started = [client startWithHost:@"" port:3389 username:@"u" domain:@""
                                        password:@"p" width:800 height:600
                                    securityMode:RDPMacSecurityModeNegotiate
                                clipboardEnabled:YES commandAsControl:YES allowLegacyTLS:NO
                        certificatePromptTimeout:5 error:&error];
            expect(!started && error != nil, @"empty host is rejected");
            error = nil;
            started = [client startWithHost:@"127.0.0.1" port:0 username:@"u" domain:@""
                                   password:@"p" width:800 height:600
                               securityMode:RDPMacSecurityModeNegotiate
                           clipboardEnabled:YES commandAsControl:YES allowLegacyTLS:NO
                   certificatePromptTimeout:5 error:&error];
            expect(!started && error != nil, @"invalid port is rejected");
            expect(![client requestDesktopSize:1024 height:768],
                   @"DisplayControl request fails without a session");
            [client sendCtrlAltDelete];
            RDPMacKeyEvent sas[16] = {0};
            const NSUInteger sasCount = RDPMacSecureAttentionSequence(sas, 16);
            expect(sasCount == 8, @"Ctrl+Alt+Delete sequence has eight key events");
            expect(RDPMacSecureAttentionSequence(NULL, 0) == 8,
                   @"Ctrl+Alt+Delete sequence length is reported without a buffer");
            expect(sas[0].scancode == 0x1D && sas[0].down &&
                       sas[1].scancode == 0x38 && sas[1].down,
                   @"Ctrl+Alt+Delete presses Control then Alt first");
            expect((sas[2].scancode & 0xFF) == 0x4F && (sas[2].scancode & 0x100) && sas[2].down &&
                       (sas[3].scancode & 0xFF) == 0x4F && (sas[3].scancode & 0x100) && !sas[3].down,
                   @"Ctrl+Alt+Delete sends the extended End scancode (E0 4F)");
            expect((sas[4].scancode & 0xFF) == 0x53 && (sas[4].scancode & 0x100) && sas[4].down &&
                       (sas[5].scancode & 0xFF) == 0x53 && (sas[5].scancode & 0x100) && !sas[5].down,
                   @"Ctrl+Alt+Delete also sends the extended Delete scancode (E0 53)");
            expect(sas[6].scancode == 0x38 && !sas[6].down &&
                       sas[7].scancode == 0x1D && !sas[7].down,
                   @"Ctrl+Alt+Delete releases Alt then Control last");
            uint8_t buffer[16] = {0};
            size_t width = 0;
            size_t height = 0;
            expect(![client copyFrameIntoBuffer:buffer capacity:sizeof(buffer) stride:16 width:&width height:&height],
                   @"no framebuffer before connect");
        }

        {
            RDPMacClient *frameClient = [RDPMacClient new];
            [frameClient framebufferConfigureWithWidth:1024 height:480];
            size_t capacity = 1024 * 480 * 4;
            void *frame = malloc(capacity);
            [frameClient framebufferConfigureWithWidth:1024 height:600];
            size_t w = 0, h = 0;
            expect(![frameClient copyFrameIntoBuffer:frame capacity:capacity stride:4096 width:&w height:&h],
                   @"resize cannot overrun a destination sized for the old height");
            free(frame);
        }

        RDPMacClient *client = [[RDPMacClient alloc] init];
        NSError *error = nil;
        expect(startToClosedPort(client, &error), @"start to 127.0.0.1:1 begins");
        expect(waitForFailure(client, 20.0), @"TCP failure reaches Failed state with message");
        printf("error text: %s\n", client.lastErrorText.UTF8String ?: "");
        expect([client.lastErrorText rangeOfString:@"не удалось" options:NSCaseInsensitiveSearch]
                   .location != NSNotFound ||
               [client.lastErrorText rangeOfString:@"подключиться" options:NSCaseInsensitiveSearch]
                   .location != NSNotFound,
               @"failure message is human readable");

        RDPMacClipboardDiagnostics *diag = [client clipboardDiagnostics];
        expect(diag != nil, @"clipboard diagnostics available");
        expect(diag.channelConnected == NO, @"clipboard channel not connected");
        expect(diag.remoteFormats.count == 0, @"no remote formats without session");

        // Restart on the same object: the previous context must be freed.
        error = nil;
        expect(startToClosedPort(client, &error), @"second start on same client succeeds");
        expect(waitForFailure(client, 20.0), @"second TCP failure reaches Failed state");

        [client disconnect];
        pumpMainQueue(0.3);
        expect(client.state == RDPMacConnectionStateFailed ||
                   client.state == RDPMacConnectionStateDisconnected,
               @"disconnect after failure is harmless");

        // Release the client; dealloc must not crash with a finished thread.
        client = nil;
        printf("client released\n");

        // A fresh client must still work after the previous one was released.
        RDPMacClient *second = [[RDPMacClient alloc] init];
        error = nil;
        expect(startToClosedPort(second, &error), @"fresh client starts after release");
        expect(waitForFailure(second, 20.0), @"fresh client fails cleanly");
        second = nil;
        printf("second client released\n");

        pumpMainQueue(0.2);

        if (gFailures == 0) {
            printf("RESULT: OK\n");
            return 0;
        }
        printf("RESULT: %d FAILURES\n", gFailures);
        return 1;
    }
}
