#import "RDPMacInternal.h"

#import <AppKit/AppKit.h>

#include <freerdp/channels/cliprdr.h>

static const NSTimeInterval RDPMacClipboardPollInterval = 0.4;
static const NSTimeInterval RDPMacClipboardRequestTimeout = 5.0;
static const NSUInteger RDPMacClipboardMaxTextBytes = 32 * 1024 * 1024;

@implementation RDPMacClipboardController
{
    CliprdrClientContext *_cliprdr;
    NSPasteboard *_pasteboard;
    NSTimer *_pollTimer;
    NSTimer *_requestTimer;
    NSDateFormatter *_timeFormatter;

    NSInteger _lastChangeCount;
    NSInteger _suppressChangeCount;
    BOOL _hasSuppressedChangeCount;

    NSString *_lastLocalText;
    NSArray<NSNumber *> *_remoteFormatIds;
    NSArray<NSString *> *_remoteFormatNames;

    uint32_t _pendingFormat;
    NSUInteger _pendingGeneration;
    BOOL _pending;

    NSString *_lastLocalAdvertise;
    NSString *_lastRemoteAdvertise;
    NSString *_lastLocalSend;
    NSString *_lastRemoteReceive;
    NSString *_lastError;
    NSString *_capabilitiesText;

    NSInteger _localAdvertiseCount;
    NSInteger _remoteAdvertiseCount;
    NSInteger _sendCount;
    NSInteger _receiveCount;
    NSInteger _failureCount;
    BOOL _invalidated;
    BOOL _synchronizationActive;
    BOOL _discardPendingResponse;
    BOOL _requestTimedOut;
    uint32_t _queuedRemoteFormat;
}

- (instancetype)initWithEnabled:(BOOL)enabled
{
    self = [super init];
    if (self) {
        _enabled = enabled;
        _synchronizationActive = YES;
        _pasteboard = [NSPasteboard generalPasteboard];
        _remoteFormatIds = @[];
        _remoteFormatNames = @[];
        _timeFormatter = [[NSDateFormatter alloc] init];
        _timeFormatter.dateFormat = @"HH:mm:ss";
        _lastChangeCount = _pasteboard.changeCount;
    }
    return self;
}

- (void)dealloc
{
    [self stopTimers];
}

- (void)log:(NSString *)message level:(NSInteger)level
{
    [self.client logMessage:message level:level];
}

- (void)notify
{
    [self.client notifyClipboardDiagnostics];
}

- (void)stopTimers
{
    [_pollTimer invalidate];
    _pollTimer = nil;
    [_requestTimer invalidate];
    _requestTimer = nil;
}

- (void)startPolling
{
    if (_pollTimer || !_enabled || !_synchronizationActive)
        return;
    __weak typeof(self) weakSelf = self;
    _pollTimer = [NSTimer scheduledTimerWithTimeInterval:RDPMacClipboardPollInterval
                                                 repeats:YES
                                                   block:^(NSTimer *timer) {
                                                       [weakSelf pollPasteboard];
                                                   }];
    // The timer must keep firing while a menu or modal panel is open.
    [[NSRunLoop mainRunLoop] addTimer:_pollTimer forMode:NSRunLoopCommonModes];
}

- (void)setSynchronizationActive:(BOOL)active
{
    if (_synchronizationActive == active)
        return;
    _synchronizationActive = active;
    if (!active) {
        [_pollTimer invalidate];
        _pollTimer = nil;
        if (_pending)
            _discardPendingResponse = YES;
        _queuedRemoteFormat = 0;
    } else if (_enabled && _monitorReady) {
        [self startPolling];
        // The Mac clipboard remains authoritative on focus changes. Remote
        // text is requested only after the next server advertisement or a
        // manual request, never from an inactive session.
        _lastChangeCount = _pasteboard.changeCount;
        [self sendLocalClipboard];
    }
    [self notify];
}

- (void)attachChannel:(CliprdrClientContext *)cliprdr
{
    @synchronized (self) {
        if (_invalidated)
            return;
        _cliprdr = cliprdr;
        _channelConnected = YES;
        _monitorReady = NO;
    }
    [self log:RDPMacLocalizedString(@"CLIPRDR: канал буфера обмена подключён") level:0];
    [self notify];
}

- (void)invalidateChannel
{
    @synchronized (self) {
        _invalidated = YES;
        _cliprdr = NULL;
        _channelConnected = NO;
        _monitorReady = NO;
        _pending = NO;
    }
}

- (void)detachChannel
{
    const BOOL wasConnected = _channelConnected;
    [self invalidateChannel];
    if (wasConnected)
        [self log:RDPMacLocalizedString(@"CLIPRDR: канал буфера обмена отключён") level:1];
    [_requestTimer invalidate];
    _requestTimer = nil;
    [_pollTimer invalidate];
    _pollTimer = nil;
    [self notify];
}

- (void)resetForNewSession
{
    _invalidated = NO;
    [_pollTimer invalidate];
    _pollTimer = nil;
    [_requestTimer invalidate];
    _requestTimer = nil;
    _pending = NO;
    _pendingFormat = 0;
    _pendingGeneration = 0;
    _requestTimedOut = NO;
    _discardPendingResponse = NO;
    _queuedRemoteFormat = 0;
    _remoteFormatIds = @[];
    _remoteFormatNames = @[];
    _lastLocalText = nil;
    _hasSuppressedChangeCount = NO;
    _lastLocalAdvertise = nil;
    _lastRemoteAdvertise = nil;
    _lastLocalSend = nil;
    _lastRemoteReceive = nil;
    _lastError = nil;
    _capabilitiesText = nil;
    _localAdvertiseCount = 0;
    _remoteAdvertiseCount = 0;
    _sendCount = 0;
    _receiveCount = 0;
    _failureCount = 0;
    _lastChangeCount = _pasteboard.changeCount;
    [self notify];
}

- (void)shutdown
{
    [self stopTimers];
    _cliprdr = NULL;
    _channelConnected = NO;
    _monitorReady = NO;
    _pending = NO;
}

- (NSString *)now
{
    return [_timeFormatter stringFromDate:[NSDate date]];
}

- (BOOL)sendCapabilities
{
    CLIPRDR_GENERAL_CAPABILITY_SET general = {0};
    general.capabilitySetType = CB_CAPSTYPE_GENERAL;
    general.capabilitySetLength = CB_CAPSTYPE_GENERAL_LEN;
    general.version = CB_CAPS_VERSION_2;
    // Text only: no file clip, no lock support, no long format names.
    general.generalFlags = 0;

    CLIPRDR_CAPABILITIES caps = {0};
    caps.common.msgType = CB_CLIP_CAPS;
    caps.cCapabilitiesSets = 1;
    caps.capabilitySets = (CLIPRDR_CAPABILITY_SET *)&general;

    UINT rc = CHANNEL_RC_BAD_INIT_HANDLE;
    @synchronized (self) {
        if (_cliprdr && _cliprdr->ClientCapabilities)
            rc = _cliprdr->ClientCapabilities(_cliprdr, &caps);
    }
    if (rc != CHANNEL_RC_OK) {
        _failureCount++;
        _lastError = [NSString stringWithFormat:RDPMacLocalizedString(@"не удалось отправить CLIPRDR capabilities (0x%08X)"),
                                                rc];
        [self log:_lastError level:2];
        [self notify];
        return NO;
    }
    return YES;
}

- (void)handleMonitorReady
{
    _monitorReady = YES;
    [self log:RDPMacLocalizedString(@"CLIPRDR: получен Monitor Ready, согласование форматов") level:0];

    if (_enabled) {
        [self sendCapabilities];
        [self startPolling];
        [self sendLocalClipboard];
    } else {
        [self log:RDPMacLocalizedString(@"CLIPRDR: канал доступен, но обмен отключён в настройках") level:1];
    }
    [self notify];
}

- (void)handleServerCapabilitiesGeneralFlags:(uint32_t)flags version:(uint32_t)version
{
    _capabilitiesText = [NSString stringWithFormat:RDPMacLocalizedString(@"версия %u, generalFlags 0x%08X"), version, flags];
    [self log:[NSString stringWithFormat:RDPMacLocalizedString(@"CLIPRDR: возможности сервера — %@"), _capabilitiesText]
         level:0];
    [self notify];
}

- (BOOL)sendLocalFormatListAndCount:(BOOL)count
{
    if (!_enabled || !_synchronizationActive || !_monitorReady)
        return NO;

    CLIPRDR_FORMAT format = {0};
    format.formatId = RDPMacClipboardFormatUnicodeText;
    format.formatName = NULL;

    CLIPRDR_FORMAT_LIST list = {0};
    list.common.msgType = CB_FORMAT_LIST;
    list.common.msgFlags = 0;
    list.numFormats = 1;
    list.formats = &format;

    UINT rc = CHANNEL_RC_BAD_INIT_HANDLE;
    @synchronized (self) {
        if (_cliprdr && _cliprdr->ClientFormatList)
            rc = _cliprdr->ClientFormatList(_cliprdr, &list);
    }
    if (rc != CHANNEL_RC_OK) {
        _failureCount++;
        _lastError = [NSString stringWithFormat:RDPMacLocalizedString(@"не удалось отправить список форматов (0x%08X)"), rc];
        [self log:_lastError level:2];
        [self notify];
        return NO;
    }

    if (count) {
        _localAdvertiseCount++;
        _lastLocalAdvertise = [NSString stringWithFormat:@"%@, CF_UNICODETEXT", [self now]];
    }
    return YES;
}

- (void)sendLocalClipboard
{
    if (!_enabled) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: отправка отключена в настройках") level:1];
        return;
    }
    if (!_synchronizationActive || !_monitorReady || !_cliprdr) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: канал ещё не готов") level:1];
        return;
    }

    NSString *text = [_pasteboard stringForType:NSPasteboardTypeString];
    if (text.length == 0) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: в буфере macOS нет текста для отправки") level:1];
        [self notify];
        return;
    }

    _lastLocalText = text;
    if ([self sendLocalFormatListAndCount:YES]) {
        [self log:[NSString stringWithFormat:RDPMacLocalizedString(@"CLIPRDR: Mac → Windows объявлен текст (%lu символов)"),
                                             (unsigned long)text.length]
             level:0];
    }
    [self notify];
}

- (void)sendFailResponseForFormat:(uint32_t)formatId
{
    CLIPRDR_FORMAT_DATA_RESPONSE response = {0};
    response.common.msgType = CB_FORMAT_DATA_RESPONSE;
    response.common.msgFlags = CB_RESPONSE_FAIL;
    response.common.dataLen = 0;
    response.requestedFormatData = NULL;
    UINT rc = CHANNEL_RC_BAD_INIT_HANDLE;
    BOOL sent = NO;
    @synchronized (self) {
        if (_cliprdr && _cliprdr->ClientFormatDataResponse) {
            rc = _cliprdr->ClientFormatDataResponse(_cliprdr, &response);
            sent = YES;
        }
    }
    if (!sent)
        return;
    if (_lastError.length == 0) {
        _lastError = [NSString stringWithFormat:RDPMacLocalizedString(@"Windows запросил неподдерживаемый формат %@"),
                                                RDPMacClipboardFormatName(formatId)];
    }
    [self log:[NSString stringWithFormat:RDPMacLocalizedString(@"CLIPRDR: %@, отправлен отказ (rc=0x%08X)"), _lastError, rc]
         level:1];
    [self notify];
}

- (void)handleServerFormatDataRequestFormat:(uint32_t)formatId
{
    if (!_enabled || !_synchronizationActive) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"буфер обмена отключён в настройках профиля");
        [self sendFailResponseForFormat:formatId];
        return;
    }

    if (formatId != RDPMacClipboardFormatUnicodeText && formatId != RDPMacClipboardFormatText) {
        _failureCount++;
        _lastError = [NSString stringWithFormat:RDPMacLocalizedString(@"Windows запросил неподдерживаемый формат %@"),
                                                RDPMacClipboardFormatName(formatId)];
        [self sendFailResponseForFormat:formatId];
        return;
    }

    NSString *text = [_pasteboard stringForType:NSPasteboardTypeString];
    if (text.length == 0) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"Windows запросил данные, но в буфере macOS нет текста");
        [self log:_lastError level:1];
        [self sendFailResponseForFormat:formatId];
        return;
    }

    if (text.length > RDPMacClipboardMaxTextBytes / 2) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"текст превышает безопасный размер для буфера обмена");
        [self log:_lastError level:2];
        [self sendFailResponseForFormat:formatId];
        return;
    }

    NSError *error = nil;
    NSData *payload = RDPMacClipboardEncodeText(text, formatId, &error);
    if (!payload) {
        _failureCount++;
        _lastError = error.localizedDescription ?: RDPMacLocalizedString(@"не удалось закодировать текст");
        [self log:_lastError level:2];
        [self sendFailResponseForFormat:formatId];
        return;
    }
    if (payload.length > RDPMacClipboardMaxTextBytes) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"текст превышает безопасный размер для буфера обмена");
        [self log:_lastError level:2];
        [self sendFailResponseForFormat:formatId];
        return;
    }

    CLIPRDR_FORMAT_DATA_RESPONSE response = {0};
    response.common.msgType = CB_FORMAT_DATA_RESPONSE;
    response.common.msgFlags = CB_RESPONSE_OK;
    response.common.dataLen = (UINT32)payload.length;
    response.requestedFormatData = payload.bytes;

    UINT rc = CHANNEL_RC_BAD_INIT_HANDLE;
    @synchronized (self) {
        if (_cliprdr && _cliprdr->ClientFormatDataResponse)
            rc = _cliprdr->ClientFormatDataResponse(_cliprdr, &response);
    }
    if (rc == CHANNEL_RC_OK) {
        _sendCount++;
        _lastLocalSend = [NSString stringWithFormat:RDPMacLocalizedString(@"%@, %@, %lu байт"), [self now],
                                                    RDPMacClipboardFormatName(formatId),
                                                    (unsigned long)payload.length];
        _lastLocalText = text;
        [self log:[NSString stringWithFormat:RDPMacLocalizedString(@"CLIPRDR: Mac → Windows отправлено %lu символов (%@)"),
                                             (unsigned long)text.length,
                                             RDPMacClipboardFormatName(formatId)]
             level:0];
    } else {
        _failureCount++;
        _lastError = [NSString stringWithFormat:RDPMacLocalizedString(@"ошибка отправки данных (0x%08X)"), rc];
        [self log:_lastError level:2];
    }
    [self notify];
}

- (void)sendFormatListResponseOK
{
    CLIPRDR_FORMAT_LIST_RESPONSE response = {0};
    response.common.msgType = CB_FORMAT_LIST_RESPONSE;
    response.common.msgFlags = CB_RESPONSE_OK;
    @synchronized (self) {
        if (_cliprdr && _cliprdr->ClientFormatListResponse)
            _cliprdr->ClientFormatListResponse(_cliprdr, &response);
    }
}

- (void)handleServerFormatListIds:(NSArray<NSNumber *> *)ids names:(NSArray<NSString *> *)names
{
    _remoteFormatIds = [ids copy];
    _remoteFormatNames = [names copy];
    _remoteAdvertiseCount++;
    _lastRemoteAdvertise =
        [NSString stringWithFormat:@"%@, %@", [self now],
                                   names.count ? [names componentsJoinedByString:@", "] : @"—"];
    [self log:[NSString stringWithFormat:RDPMacLocalizedString(@"CLIPRDR: Windows → Mac список форматов: %@"),
                                         _lastRemoteAdvertise]
         level:0];
    // The peer expects an acknowledgement for its format list even if none of
    // the advertised formats is supported.
    [self sendFormatListResponseOK];

    if (!_enabled || !_synchronizationActive) {
        [self notify];
        return;
    }

    BOOL hasUnicode = [ids containsObject:@(RDPMacClipboardFormatUnicodeText)];
    BOOL hasAnsi = [ids containsObject:@(RDPMacClipboardFormatText)];
    if (!hasUnicode && !hasAnsi) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: в буфере Windows нет текста (изображения/файлы пока не поддерживаются)")
             level:0];
        [self notify];
        return;
    }

    [self requestRemoteFormat:hasUnicode ? RDPMacClipboardFormatUnicodeText
                                        : RDPMacClipboardFormatText];
    [self notify];
}

- (void)handleServerFormatListResponseFlags:(uint16_t)flags
{
    if (flags & CB_RESPONSE_FAIL)
        [self log:RDPMacLocalizedString(@"CLIPRDR: Windows отклонил список форматов Mac") level:1];
    else
        [self log:RDPMacLocalizedString(@"CLIPRDR: Windows подтвердил список форматов Mac") level:0];
    [self notify];
}

- (void)requestRemoteFormat:(uint32_t)formatId
{
    if (!_enabled || !_synchronizationActive || !_monitorReady) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: канал не готов для запроса данных") level:1];
        return;
    }

    if (_pending) {
        _queuedRemoteFormat = formatId;
        _discardPendingResponse = YES;
        return;
    }

    CLIPRDR_FORMAT_DATA_REQUEST request = {0};
    request.common.msgType = CB_FORMAT_DATA_REQUEST;
    request.common.msgFlags = 0;
    request.requestedFormatId = formatId;

    _pending = YES;
    _requestTimedOut = NO;
    _pendingFormat = formatId;
    _pendingGeneration++;

    UINT rc = CHANNEL_RC_BAD_INIT_HANDLE;
    @synchronized (self) {
        if (!_cliprdr || !_cliprdr->ClientFormatDataRequest) {
            _pending = NO;
            return;
        }
        rc = _cliprdr->ClientFormatDataRequest(_cliprdr, &request);
    }
    if (rc != CHANNEL_RC_OK) {
        _pending = NO;
        _failureCount++;
        _lastError = [NSString stringWithFormat:RDPMacLocalizedString(@"не удалось запросить данные (0x%08X)"), rc];
        [self log:_lastError level:2];
        [self notify];
        return;
    }

    [_requestTimer invalidate];
    __weak typeof(self) weakSelf = self;
    _requestTimer = [NSTimer scheduledTimerWithTimeInterval:RDPMacClipboardRequestTimeout
                                                    repeats:NO
                                                      block:^(NSTimer *timer) {
                                                          [weakSelf requestDidTimeOut];
                                                      }];
    [[NSRunLoop mainRunLoop] addTimer:_requestTimer forMode:NSRunLoopCommonModes];

    [self log:[NSString stringWithFormat:RDPMacLocalizedString(@"CLIPRDR: у Windows запрошен %@"),
                                         RDPMacClipboardFormatName(formatId)]
         level:0];
    [self notify];
}

- (void)requestDidTimeOut
{
    if (!_pending)
        return;
    // CLIPRDR responses carry no request ID: keep the outstanding request
    // until its reply arrives, otherwise a late reply could satisfy a newer
    // request with the wrong format. It must never update the pasteboard.
    _discardPendingResponse = YES;
    _requestTimedOut = YES;
    _failureCount++;
    _lastError = [NSString stringWithFormat:RDPMacLocalizedString(@"тайм-аут ожидания буфера обмена (%.0f с)"),
                                            RDPMacClipboardRequestTimeout];
    [self log:[NSString stringWithFormat:@"CLIPRDR: %@", _lastError] level:2];
    [self notify];
}

- (void)applyRemoteText:(NSString *)text format:(uint32_t)formatId byteLength:(NSUInteger)byteLength
{
    NSString *current = [_pasteboard stringForType:NSPasteboardTypeString];
    if (current && [current isEqualToString:text]) {
        _hasSuppressedChangeCount = YES;
        _suppressChangeCount = _pasteboard.changeCount;
        _lastChangeCount = _suppressChangeCount;
        _lastLocalText = text;
        _receiveCount++;
        _lastRemoteReceive = [NSString stringWithFormat:RDPMacLocalizedString(@"%@, %@, %lu байт (без изменений)"), [self now],
                                                        RDPMacClipboardFormatName(formatId),
                                                        (unsigned long)byteLength];
        [self log:RDPMacLocalizedString(@"CLIPRDR: текст Windows уже совпадает с буфером macOS") level:0];
        [self notify];
        return;
    }

    [_pasteboard clearContents];
    const BOOL ok = [_pasteboard setString:text forType:NSPasteboardTypeString];
    if (!ok) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"не удалось записать текст в буфер обмена macOS");
        [self log:_lastError level:2];
        [self notify];
        return;
    }

    _hasSuppressedChangeCount = YES;
    _suppressChangeCount = _pasteboard.changeCount;
    _lastChangeCount = _suppressChangeCount;
    _lastLocalText = text;
    _receiveCount++;
    _lastRemoteReceive = [NSString stringWithFormat:RDPMacLocalizedString(@"%@, %@, %lu байт"), [self now],
                                                    RDPMacClipboardFormatName(formatId),
                                                    (unsigned long)byteLength];
    [self log:[NSString stringWithFormat:RDPMacLocalizedString(@"CLIPRDR: Windows → Mac получено %lu символов (содержимое в журнал не пишется)"),
                                         (unsigned long)text.length]
         level:0];
    [self notify];
}

- (void)handleServerFormatDataResponse:(NSData *)data flags:(uint16_t)flags
{
    if (!_pending)
        return;
    const uint32_t format = _pendingFormat;
    const BOOL discard = _discardPendingResponse || !_synchronizationActive;
    _pending = NO;
    _requestTimedOut = NO;
    _discardPendingResponse = NO;
    [_requestTimer invalidate];
    _requestTimer = nil;

    const uint32_t queuedFormat = _queuedRemoteFormat;
    _queuedRemoteFormat = 0;
    if (queuedFormat && _synchronizationActive && _enabled) {
        [self requestRemoteFormat:queuedFormat];
        return;
    }
    if (!_enabled || discard) {
        [self notify];
        return;
    }

    if (flags & CB_RESPONSE_FAIL) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"Windows не смог предоставить текст буфера обмена");
        [self log:[NSString stringWithFormat:@"CLIPRDR: %@", _lastError] level:1];
        [self notify];
        return;
    }

    if (data.length == 0) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"Windows вернул пустые данные буфера обмена");
        [self log:_lastError level:1];
        [self notify];
        return;
    }

    if (data.length > RDPMacClipboardMaxTextBytes) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"ответ Windows превышает безопасный размер буфера обмена");
        [self log:_lastError level:2];
        [self notify];
        return;
    }

    NSString *text = RDPMacClipboardDecodeText(data, format);
    if (!text) {
        _failureCount++;
        _lastError = RDPMacLocalizedString(@"не удалось декодировать текст из буфера Windows");
        [self log:_lastError level:2];
        [self notify];
        return;
    }

    // Do not echo our own content back: some servers request client data and
    // then advertise the very same text back to the client.
    if (_lastLocalText && [text isEqualToString:_lastLocalText]) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: эхо собственного текста проигнорировано") level:0];
        _receiveCount++;
        _lastRemoteReceive = [NSString stringWithFormat:RDPMacLocalizedString(@"%@, %@, %lu байт (эхо)"), [self now],
                                                        RDPMacClipboardFormatName(format),
                                                        (unsigned long)data.length];
        [self notify];
        return;
    }

    [self applyRemoteText:text format:format byteLength:data.length];
}

- (void)pollPasteboard
{
    if (!_enabled || !_synchronizationActive || !_monitorReady || !_cliprdr)
        return;

    const NSInteger changeCount = _pasteboard.changeCount;
    if (changeCount == _lastChangeCount)
        return;
    _lastChangeCount = changeCount;

    if (_hasSuppressedChangeCount && changeCount == _suppressChangeCount) {
        _hasSuppressedChangeCount = NO;
        return;
    }

    NSString *text = [_pasteboard stringForType:NSPasteboardTypeString];
    if (text.length == 0) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: локальный буфер изменился, но текста в нём нет") level:0];
        return;
    }
    if (_lastLocalText && [text isEqualToString:_lastLocalText])
        return;

    _lastLocalText = text;
    if ([self sendLocalFormatListAndCount:YES]) {
        [self log:[NSString stringWithFormat:RDPMacLocalizedString(@"CLIPRDR: Mac → Windows локальный буфер изменился (%lu символов)"),
                                             (unsigned long)text.length]
             level:0];
        [self notify];
    }
}

- (void)requestRemoteClipboard
{
    if (!_enabled) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: обмен отключён в настройках") level:1];
        return;
    }
    if (!_synchronizationActive || !_monitorReady || !_cliprdr) {
        [self log:RDPMacLocalizedString(@"CLIPRDR: канал ещё не готов для запроса из Windows") level:1];
        [self notify];
        return;
    }

    uint32_t format = RDPMacClipboardFormatUnicodeText;
    if (_remoteFormatIds.count > 0) {
        if (![_remoteFormatIds containsObject:@(RDPMacClipboardFormatUnicodeText)]) {
            if ([_remoteFormatIds containsObject:@(RDPMacClipboardFormatText)])
                format = RDPMacClipboardFormatText;
            else {
                [self log:RDPMacLocalizedString(@"CLIPRDR: в текущем буфере Windows нет текстового формата") level:1];
                [self notify];
                return;
            }
        }
    }

    [self requestRemoteFormat:format];
}

- (void)resync
{
    [self log:RDPMacLocalizedString(@"CLIPRDR: ручная ресинхронизация буфера обмена") level:0];
    [self sendLocalClipboard];
    [self requestRemoteClipboard];
}

- (void)handleChannelDisconnected
{
    [self detachChannel];
}

- (NSString *)stateDescription
{
    if (!_enabled)
        return RDPMacLocalizedString(@"обмен отключён в настройках");
    if (_pending && _requestTimedOut)
        return RDPMacLocalizedString(@"Сервер не отвечает. Переподключите сессию для восстановления буфера.");
    if (!_channelConnected)
        return RDPMacLocalizedString(@"канал не подключён");
    if (!_synchronizationActive)
        return RDPMacLocalizedString(@"приостановлен: сессия не активна");
    if (!_monitorReady)
        return RDPMacLocalizedString(@"ожидание Monitor Ready");
    if (_pending)
        return [NSString stringWithFormat:RDPMacLocalizedString(@"ожидание данных (%@)"),
                                          RDPMacClipboardFormatName(_pendingFormat)];
    if (_capabilitiesText)
        return [NSString stringWithFormat:RDPMacLocalizedString(@"готов; сервер: %@"), _capabilitiesText];
    return RDPMacLocalizedString(@"готов");
}

- (RDPMacClipboardDiagnostics *)diagnostics
{
    RDPMacClipboardDiagnostics *d = [[RDPMacClipboardDiagnostics alloc] init];
    d.enabled = _enabled;
    d.requiresReconnect = _pending && _requestTimedOut;
    d.channelConnected = _channelConnected;
    d.monitorReady = _monitorReady;
    d.localFormats = _enabled ? @[ @"CF_UNICODETEXT" ] : @[];
    d.remoteFormats = _remoteFormatNames.count ? _remoteFormatNames : @[];
    d.lastLocalAdvertise = _lastLocalAdvertise;
    d.lastRemoteAdvertise = _lastRemoteAdvertise;
    d.lastLocalSend = _lastLocalSend;
    d.lastRemoteReceive = _lastRemoteReceive;
    d.pendingRequest = _pending
        ? [NSString stringWithFormat:RDPMacLocalizedString(@"%@ с %@"), RDPMacClipboardFormatName(_pendingFormat),
                                     [self now]]
        : nil;
    d.localAdvertiseCount = _localAdvertiseCount;
    d.remoteAdvertiseCount = _remoteAdvertiseCount;
    d.sendCount = _sendCount;
    d.receiveCount = _receiveCount;
    d.failureCount = _failureCount;
    d.lastError = _lastError;
    d.stateDescription = [self stateDescription];
    return d;
}

- (NSString *)diagnosticsReport
{
    RDPMacClipboardDiagnostics *d = [self diagnostics];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:@"CLIPRDR diagnostics (no clipboard contents)"];
    [lines addObject:[NSString stringWithFormat:@"state: %@", d.stateDescription]];
    [lines addObject:[NSString stringWithFormat:@"enabled: %@", d.enabled ? @"yes" : @"no"]];
    [lines addObject:[NSString stringWithFormat:@"channel connected: %@",
                                                d.channelConnected ? @"yes" : @"no"]];
    [lines addObject:[NSString stringWithFormat:@"monitor ready: %@", d.monitorReady ? @"yes" : @"no"]];
    [lines addObject:[NSString stringWithFormat:@"local formats: %@",
                                                [d.localFormats componentsJoinedByString:@", "]]];
    [lines addObject:[NSString stringWithFormat:@"remote formats: %@",
                                                d.remoteFormats.count
                                                    ? [d.remoteFormats componentsJoinedByString:@", "]
                                                    : @"-"]];
    [lines addObject:[NSString stringWithFormat:@"local advertisements: %ld, remote: %ld",
                                                (long)d.localAdvertiseCount,
                                                (long)d.remoteAdvertiseCount]];
    [lines addObject:[NSString stringWithFormat:@"sent: %ld, received: %ld, failures: %ld",
                                                (long)d.sendCount, (long)d.receiveCount,
                                                (long)d.failureCount]];
    [lines addObject:[NSString stringWithFormat:@"last local advertise: %@",
                                                d.lastLocalAdvertise ?: @"-"]];
    [lines addObject:[NSString stringWithFormat:@"last remote advertise: %@",
                                                d.lastRemoteAdvertise ?: @"-"]];
    [lines addObject:[NSString stringWithFormat:@"last local send: %@", d.lastLocalSend ?: @"-"]];
    [lines addObject:[NSString stringWithFormat:@"last remote receive: %@",
                                                d.lastRemoteReceive ?: @"-"]];
    [lines addObject:[NSString stringWithFormat:@"pending request: %@", d.pendingRequest ?: @"-"]];
    [lines addObject:[NSString stringWithFormat:@"last error: %@", d.lastError ?: @"-"]];
    [lines addObject:RDPMacLocalizedString(@"Содержимое буфера обмена в отчёт не записывается.")];
    return [lines componentsJoinedByString:@"\n"];
}

@end
