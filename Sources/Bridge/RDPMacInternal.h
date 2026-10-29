//
//  RDPMacInternal.h
//  Private bridge declarations shared by the Objective-C implementation files.
//

#import "RDPMacBridge.h"
#import "RDPMacClipboardText.h"

#include <freerdp/freerdp.h>
#include <freerdp/client.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/client/disp.h>
#include <freerdp/channels/cliprdr.h>
#include <freerdp/event.h>

@class RDPMacClient;
@class RDPMacClipboardController;

typedef struct rdp_mac_context
{
    rdpClientContext common;
    __unsafe_unretained RDPMacClient *owner;
    __unsafe_unretained RDPMacClipboardController *clipboard;
    DispClientContext *disp;
} RDPMacContext;

@interface RDPMacClient (Internal)
- (void)logMessage:(NSString *)message level:(NSInteger)level;
- (void)notifyClipboardDiagnostics;
- (BOOL)isSessionUsable;
- (void)clipboardThreadMonitorReady;
- (void)clipboardThreadCapabilities:(uint32_t)generalFlags version:(uint32_t)version;
- (void)clipboardThreadFormatList:(NSArray<NSNumber *> *)formatIds
                            names:(NSArray<NSString *> *)formatNames;
- (void)clipboardThreadFormatListResponse:(uint16_t)flags;
- (void)clipboardThreadFormatDataRequest:(uint32_t)formatId;
- (void)clipboardThreadFormatDataResponse:(NSData *)data flags:(uint16_t)flags;
- (void)clipboardThreadDisconnected;
@end

/// All methods must be called on the main thread.
@interface RDPMacClipboardController : NSObject
@property (nonatomic, weak, nullable) RDPMacClient *client;
@property (nonatomic, assign, readonly) BOOL enabled;
@property (nonatomic, assign, readonly) BOOL channelConnected;
@property (nonatomic, assign, readonly) BOOL monitorReady;

- (instancetype)initWithEnabled:(BOOL)enabled;
- (void)attachChannel:(CliprdrClientContext *)cliprdr;
- (void)detachChannel;
/// Thread-safe: drops the channel pointer before FreeRDP frees the context.
/// Does not touch timers or the UI.
- (void)invalidateChannel;
- (void)resetForNewSession;
- (void)shutdown;

- (void)handleMonitorReady;
- (void)handleServerCapabilitiesGeneralFlags:(uint32_t)flags version:(uint32_t)version;
- (void)handleServerFormatListIds:(NSArray<NSNumber *> *)ids names:(NSArray<NSString *> *)names;
- (void)handleServerFormatListResponseFlags:(uint16_t)flags;
- (void)handleServerFormatDataRequestFormat:(uint32_t)formatId;
- (void)handleServerFormatDataResponse:(NSData *)data flags:(uint16_t)flags;
- (void)handleChannelDisconnected;

- (void)sendLocalClipboard;
- (void)requestRemoteClipboard;
- (void)resync;
- (RDPMacClipboardDiagnostics *)diagnostics;
- (NSString *)diagnosticsReport;
@end
