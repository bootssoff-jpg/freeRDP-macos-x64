//
//  RDPMacBridge.h
//  Objective-C bridge between the AppKit UI and libfreerdp (FreeRDP 3.32.x).
//
//  This header is imported by Swift through RDPMac-Bridging-Header.h and must
//  therefore stay free of FreeRDP headers.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RDPMacConnectionState) {
    RDPMacConnectionStateIdle = 0,
    RDPMacConnectionStateConnecting,
    RDPMacConnectionStateConnected,
    RDPMacConnectionStateDisconnecting,
    RDPMacConnectionStateDisconnected,
    RDPMacConnectionStateFailed
};

typedef NS_ENUM(NSInteger, RDPMacSecurityMode) {
    /// NLA (CredSSP) with TLS fallback. Legacy RDP security is disabled.
    RDPMacSecurityModeNegotiate = 0,
    /// TLS only, no NLA.
    RDPMacSecurityModeTLS = 1,
    /// Legacy RDP security. Explicitly opt-in, not secure.
    RDPMacSecurityModeLegacyRDP = 2
};

typedef NS_ENUM(NSInteger, RDPMacCertificateDecision) {
    RDPMacCertificateDecisionReject = 0,
    RDPMacCertificateDecisionAcceptOnce = 1,
    RDPMacCertificateDecisionAcceptAndRemember = 2
};

/// Public certificate data shown to the user before a connection is accepted.
@interface RDPMacCertificateInfo : NSObject
@property (nonatomic, copy) NSString *hostname;
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *issuer;
@property (nonatomic, copy) NSString *fingerprintSHA256;
@property (nonatomic, assign) BOOL changed;
@property (nonatomic, copy) NSString *details;
@end

/// Clipboard channel diagnostics. Never contains clipboard contents.
@interface RDPMacClipboardDiagnostics : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL channelConnected;
@property (nonatomic, assign) BOOL monitorReady;
@property (nonatomic, copy) NSArray<NSString *> *localFormats;
@property (nonatomic, copy) NSArray<NSString *> *remoteFormats;
@property (nonatomic, copy, nullable) NSString *lastLocalAdvertise;
@property (nonatomic, copy, nullable) NSString *lastRemoteAdvertise;
@property (nonatomic, copy, nullable) NSString *lastLocalSend;
@property (nonatomic, copy, nullable) NSString *lastRemoteReceive;
@property (nonatomic, copy, nullable) NSString *pendingRequest;
@property (nonatomic, assign) NSInteger localAdvertiseCount;
@property (nonatomic, assign) NSInteger remoteAdvertiseCount;
@property (nonatomic, assign) NSInteger sendCount;
@property (nonatomic, assign) NSInteger receiveCount;
@property (nonatomic, assign) NSInteger failureCount;
@property (nonatomic, copy, nullable) NSString *lastError;
@property (nonatomic, copy) NSString *stateDescription;
@end

@class RDPMacClient;

@protocol RDPMacClientDelegate <NSObject>
@optional
- (void)rdpClient:(RDPMacClient *)client didChangeState:(RDPMacConnectionState)state
          message:(NSString *)message;
- (void)rdpClientDidConnect:(RDPMacClient *)client;
- (void)rdpClient:(RDPMacClient *)client
    didResizeToWidth:(NSUInteger)width
             height:(NSUInteger)height;
/// Rect is expressed in remote framebuffer pixels, origin top-left.
- (void)rdpClient:(RDPMacClient *)client didUpdateFrameInRect:(CGRect)rect;
- (void)rdpClient:(RDPMacClient *)client
    didUpdateClipboardDiagnostics:(RDPMacClipboardDiagnostics *)diagnostics;
- (void)rdpClient:(RDPMacClient *)client didLogMessage:(NSString *)message level:(NSInteger)level;
- (void)rdpClient:(RDPMacClient *)client
    didRequestCertificateApproval:(RDPMacCertificateInfo *)info
                       completion:(void (^)(RDPMacCertificateDecision decision))completion;
- (void)rdpClient:(RDPMacClient *)client didDisconnectWithError:(nullable NSString *)error;
@end

@interface RDPMacClient : NSObject

@property (nonatomic, weak, nullable) id<RDPMacClientDelegate> delegate;

@property (nonatomic, readonly) RDPMacConnectionState state;
/// Last human readable error (Russian UI text). Never contains the password.
@property (nonatomic, readonly, nullable) NSString *lastErrorText;
/// YES when the last failed attempt stopped during the TLS handshake.
/// Certificate rejection is not reported as a TLS failure.
@property (nonatomic, readonly) BOOL lastErrorWasTLS;

@property (nonatomic, readonly) size_t frameWidth;
@property (nonatomic, readonly) size_t frameHeight;
@property (nonatomic, readonly) size_t frameStride;

/// Library-level smoke test used by `--selftest` (no server required).
+ (NSString *)selfTestReport;

/// Starts a background connection thread. Returns NO only for invalid input.
- (BOOL)startWithHost:(NSString *)host
                  port:(NSInteger)port
              username:(NSString *)username
                domain:(NSString *)domain
              password:(NSString *)password
                 width:(NSUInteger)width
                height:(NSUInteger)height
          securityMode:(RDPMacSecurityMode)securityMode
     clipboardEnabled:(BOOL)clipboardEnabled
     commandAsControl:(BOOL)commandAsControl
       allowLegacyTLS:(BOOL)allowLegacyTLS
 certificatePromptTimeout:(NSTimeInterval)timeout
                 error:(NSError *_Nullable *_Nullable)error;

/// Asynchronous. Safe to call repeatedly.
- (void)disconnect;

/// Sends the RDP equivalent of Ctrl+Alt+Delete (Ctrl+Alt+End).
- (void)sendCtrlAltDelete;

/// Requests a new remote desktop size through the DisplayControl channel.
- (BOOL)requestDesktopSize:(NSUInteger)width height:(NSUInteger)height;

// Input. Coordinates are framebuffer pixels with origin at the top-left.
- (void)sendMouseMoveToX:(int)x y:(int)y;
- (void)sendMouseButton:(int)button down:(BOOL)down x:(int)x y:(int)y;
- (void)sendMouseWheelHorizontal:(BOOL)horizontal points:(double)points x:(int)x y:(int)y;
- (void)sendKeyEventWithKeyCode:(unsigned short)keyCode
                     characters:(NSString *)characters
                      modifiers:(NSUInteger)modifiers
                           down:(BOOL)down
                         repeat:(BOOL)isRepeat;

/// Synchronizes Shift/Ctrl/Alt/Command/CapsLock state with the remote session.
- (void)sendModifierFlags:(NSUInteger)modifiers;

/// Copies the latest frame into dst (BGRA, little-endian).
/// Returns NO if no frame is available.
- (BOOL)copyFrameIntoBuffer:(void *)dst
                     stride:(size_t)stride
                      width:(size_t *)width
                     height:(size_t *)height;

/// Returns and clears the accumulated dirty rect (remote pixels, top-left origin).
- (CGRect)takeDirtyRect;

- (RDPMacClipboardDiagnostics *)clipboardDiagnostics;
/// Re-advertise the local clipboard to the remote side (Mac -> Windows).
- (void)clipboardSendLocal;
/// Ask the remote side for its Unicode clipboard text (Windows -> Mac).
- (void)clipboardRequestRemote;
/// Re-run the full negotiation in both directions.
- (void)clipboardResync;

@end

NS_ASSUME_NONNULL_END
