//
//  RDPMacModels.m
//  Plain data objects exposed to Swift.
//

#import "RDPMacBridge.h"

@implementation RDPMacCertificateInfo
@end

@implementation RDPMacClipboardDiagnostics

- (instancetype)init
{
    self = [super init];
    if (self) {
        _localFormats = @[];
        _remoteFormats = @[];
        _stateDescription = RDPMacLocalizedString(@"не подключено");
    }
    return self;
}

@end
