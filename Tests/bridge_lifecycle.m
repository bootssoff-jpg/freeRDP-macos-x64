//
//  bridge_lifecycle.m
//  Exercises the real connection lifecycle without a reachable RDP server:
//  argument validation, TCP failure, state propagation, resource release and
//  a second start on the same object.
//

#import <Foundation/Foundation.h>
#import "RDPMacBridge.h"

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

static BOOL startToClosedPort(RDPMacClient *client, NSError **error)
{
    return [client startWithHost:@"127.0.0.1"
                            port:1
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

int main(void)
{
    @autoreleasepool {
        printf("%s", RDPMacClient.selfTestReport.UTF8String);

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
            uint8_t buffer[16] = {0};
            size_t width = 0;
            size_t height = 0;
            expect(![client copyFrameIntoBuffer:buffer stride:16 width:&width height:&height],
                   @"no framebuffer before connect");
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
