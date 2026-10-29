//
//  RDPMacClient.m
//  Native FreeRDP client bridge: connection lifecycle, GDI framebuffer,
//  input, DisplayControl and the CLIPRDR channel glue.
//

#import "RDPMacInternal.h"

#import <AppKit/AppKit.h>

#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/input.h>
#include <freerdp/scancode.h>
#include <freerdp/settings.h>
#include <freerdp/error.h>
#include <freerdp/crypto/certificate.h>
#include <freerdp/utils/helpers.h>
#include <freerdp/version.h>
#include <freerdp/build-config.h>
#include <freerdp/client/channels.h>
#include <freerdp/channels/channels.h>
#include <freerdp/channels/disp.h>
#include <winpr/synch.h>
#include <winpr/input.h>
#include <winpr/version.h>

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static NSString *const RDPMacErrorDomain = @"RDPMacErrorDomain";
static const NSUInteger RDPMacMaxFrameDimension = 8192;

static NSString *RDPMacErrorText(UINT32 code)
{
    switch (code) {
        case FREERDP_ERROR_SUCCESS:
            return @"Соединение завершено";
        case FREERDP_ERROR_DNS_ERROR:
        case FREERDP_ERROR_DNS_NAME_NOT_FOUND:
            return @"Не удалось разрешить имя сервера (DNS). Проверьте адрес и сеть.";
        case FREERDP_ERROR_CONNECT_FAILED:
        case FREERDP_ERROR_CONNECT_TRANSPORT_FAILED:
            return @"Не удалось подключиться к серверу. Проверьте адрес, порт, сеть и "
                   @"брандмауэр.";
        case FREERDP_ERROR_TLS_CONNECT_FAILED:
            return @"Ошибка TLS. Сертификат сервера не принят или шифрование недоступно.";
        case FREERDP_ERROR_SECURITY_NEGO_CONNECT_FAILED:
            return @"Не удалось согласовать параметры безопасности (NLA/TLS).";
        case FREERDP_ERROR_AUTHENTICATION_FAILED:
            return @"Ошибка аутентификации NLA/CredSSP. Проверьте домен, логин и пароль.";
        case FREERDP_ERROR_CONNECT_LOGON_FAILURE:
        case FREERDP_ERROR_CONNECT_WRONG_PASSWORD:
            return @"Неверное имя пользователя или пароль.";
        case FREERDP_ERROR_CONNECT_ACCOUNT_LOCKED_OUT:
            return @"Учётная запись заблокирована на сервере.";
        case FREERDP_ERROR_CONNECT_ACCOUNT_DISABLED:
            return @"Учётная запись отключена на сервере.";
        case FREERDP_ERROR_CONNECT_ACCOUNT_EXPIRED:
            return @"Срок действия учётной записи истёк.";
        case FREERDP_ERROR_CONNECT_PASSWORD_EXPIRED:
        case FREERDP_ERROR_CONNECT_PASSWORD_CERTAINLY_EXPIRED:
            return @"Срок действия пароля истёк. Смените пароль на сервере.";
        case FREERDP_ERROR_CONNECT_PASSWORD_MUST_CHANGE:
            return @"Сервер требует сменить пароль при входе.";
        case FREERDP_ERROR_CONNECT_ACCESS_DENIED:
        case FREERDP_ERROR_INSUFFICIENT_PRIVILEGES:
            return @"Доступ запрещён. У пользователя нет права на интерактивный вход.";
        case FREERDP_ERROR_CONNECT_ACCOUNT_RESTRICTION:
            return @"Ограничение учётной записи: вход с этого клиента запрещён.";
        case FREERDP_ERROR_CONNECT_LOGON_TYPE_NOT_GRANTED:
            return @"Тип входа не разрешён для этой учётной записи.";
        case FREERDP_ERROR_CONNECT_NO_OR_MISSING_CREDENTIALS:
            return @"Не заданы учётные данные. Введите пользователя и пароль.";
        case FREERDP_ERROR_CONNECT_CANCELLED:
            return @"Подключение отменено.";
        case FREERDP_ERROR_CONNECT_ACTIVATION_TIMEOUT:
            return @"Сервер не ответил вовремя (тайм-аут).";
        case FREERDP_ERROR_CONNECT_TARGET_BOOTING:
            return @"Удалённый компьютер ещё загружается. Повторите попытку позже.";
        default:
            break;
    }

    const char *text = freerdp_get_last_error_string(code);
    if (text && text[0] != '\0')
        return [NSString stringWithFormat:@"Ошибка FreeRDP: %s (код 0x%08X)", text, code];
    return [NSString stringWithFormat:@"Ошибка FreeRDP (код 0x%08X)", code];
}

static NSString *RDPMacTakeString(char *value)
{
    if (!value)
        return @"";
    NSString *result = [NSString stringWithUTF8String:value] ?: @"";
    free(value);
    return result;
}

static RDPMacCertificateInfo *RDPMacCertificateInfoFromPEM(NSData *pem, NSString *host,
                                                           NSInteger port, BOOL changed)
{
    RDPMacCertificateInfo *info = [[RDPMacCertificateInfo alloc] init];
    info.hostname = host;
    info.port = port;
    info.changed = changed;
    info.subject = @"—";
    info.issuer = @"—";
    info.fingerprintSHA256 = @"—";

    NSString *pemString = [[NSString alloc] initWithData:pem encoding:NSUTF8StringEncoding];
    rdpCertificate *cert = pemString ? freerdp_certificate_new_from_pem(pemString.UTF8String) : NULL;
    if (cert) {
        info.subject = RDPMacTakeString(freerdp_certificate_get_subject(cert));
        info.issuer = RDPMacTakeString(freerdp_certificate_get_issuer(cert));
        info.fingerprintSHA256 =
            RDPMacTakeString(freerdp_certificate_get_fingerprint_by_hash(cert, "sha256"));
        freerdp_certificate_free(cert);
    }
    if (info.subject.length == 0)
        info.subject = @"—";
    if (info.issuer.length == 0)
        info.issuer = @"—";
    if (info.fingerprintSHA256.length == 0)
        info.fingerprintSHA256 = @"—";
    info.details = [NSString stringWithFormat:@"Сервер: %@:%ld\nСубъект: %@\nИздатель: %@\n"
                                              @"SHA-256: %@\nСертификат изменён: %@",
                                              host, (long)port, info.subject, info.issuer,
                                              info.fingerprintSHA256, changed ? @"да" : @"нет"];
    return info;
}

@interface RDPMacClient (Callbacks)
- (void)logMessage:(NSString *)message level:(NSInteger)level;
- (void)framebufferConfigureWithWidth:(size_t)width height:(size_t)height;
- (void)framebufferDidResizeWidth:(size_t)width height:(size_t)height;
- (void)copyFrameRegionFromBuffer:(const uint8_t *)buffer
                           stride:(size_t)stride
                                x:(int32_t)x
                                y:(int32_t)y
                            width:(int32_t)width
                           height:(int32_t)height;
- (int)certificateDecisionForPEM:(NSData *)pem
                        hostname:(NSString *)hostname
                            port:(NSInteger)port
                         changed:(BOOL)changed;
- (int)certificateDecisionWithSubject:(NSString *)subject
                               issuer:(NSString *)issuer
                          fingerprint:(NSString *)fingerprint
                             hostname:(NSString *)hostname
                                 port:(NSInteger)port
                              changed:(BOOL)changed;
- (void)clipboardThreadMonitorReady;
- (void)clipboardThreadCapabilities:(uint32_t)generalFlags version:(uint32_t)version;
- (void)clipboardThreadFormatList:(NSArray<NSNumber *> *)formatIds
                            names:(NSArray<NSString *> *)formatNames;
- (void)clipboardThreadFormatListResponse:(uint16_t)flags;
- (void)clipboardThreadFormatDataRequest:(uint32_t)formatId;
- (void)clipboardThreadFormatDataResponse:(NSData *)data flags:(uint16_t)flags;
- (void)clipboardThreadDisconnected;
- (void)syncModifiersLocked:(NSEventModifierFlags)modifiers input:(rdpInput *)input;
- (void)sendScancodeForKeyCode:(unsigned short)keyCode down:(BOOL)down input:(rdpInput *)input;
- (BOOL)shouldSendUnicodeForCharacters:(NSString *)characters
                             modifiers:(NSEventModifierFlags)modifiers;
@end

static BOOL RDPMacScancodeForKeyCode(unsigned short keyCode, uint8_t *code, uint16_t *flags)
{
    if (!code || !flags)
        return NO;
    const DWORD vk = GetVirtualKeyCodeFromKeycode(keyCode, WINPR_KEYCODE_TYPE_APPLE);
    if (vk == 0)
        return NO;
    const DWORD scancode = GetVirtualScanCodeFromVirtualKeyCode(vk, 4);
    if (scancode == 0)
        return NO;
    *code = (uint8_t)(scancode & 0xFF);
    *flags = (scancode & 0x100) ? KBD_FLAGS_EXTENDED : 0;
    return YES;
}

static void RDPMacSendScancode(rdpInput *input, uint32_t scancode, BOOL down)
{
    if (!input)
        return;
    uint16_t flags = down ? KBD_FLAGS_DOWN : KBD_FLAGS_RELEASE;
    if (scancode & 0x100)
        flags |= KBD_FLAGS_EXTENDED;
    freerdp_input_send_keyboard_event(input, flags, (UINT8)(scancode & 0xFF));
}

static void RDPMacSendUnicodeUnit(rdpInput *input, uint16_t unit)
{
    if (!input)
        return;
    freerdp_input_send_unicode_keyboard_event(input, KBD_FLAGS_DOWN, unit);
    freerdp_input_send_unicode_keyboard_event(input, KBD_FLAGS_RELEASE, unit);
}

static RDPMacClient *RDPMacOwner(rdpContext *context)
{
    if (!context)
        return nil;
    RDPMacContext *ctx = (RDPMacContext *)context;
    return ctx->owner;
}

static BOOL rdp_client_global_init(void)
{
    return TRUE;
}

static void rdp_client_global_uninit(void)
{
}

static int rdp_client_start(rdpContext *context)
{
    (void)context;
    return 0;
}

static int rdp_client_stop(rdpContext *context)
{
    (void)context;
    return 0;
}

static BOOL rdp_pre_connect(freerdp *instance);
static BOOL rdp_post_connect(freerdp *instance);
static void rdp_post_disconnect(freerdp *instance);
static void rdp_channel_connected(void *context, const ChannelConnectedEventArgs *e);
static void rdp_channel_disconnected(void *context, const ChannelDisconnectedEventArgs *e);

static UINT rdp_clip_monitor_ready(CliprdrClientContext *clip,
                                   const CLIPRDR_MONITOR_READY *monitorReady);
static UINT rdp_clip_server_capabilities(CliprdrClientContext *clip,
                                         const CLIPRDR_CAPABILITIES *capabilities);
static UINT rdp_clip_server_format_list(CliprdrClientContext *clip,
                                        const CLIPRDR_FORMAT_LIST *formatList);
static UINT rdp_clip_server_format_list_response(CliprdrClientContext *clip,
                                                 const CLIPRDR_FORMAT_LIST_RESPONSE *response);
static UINT rdp_clip_server_format_data_request(CliprdrClientContext *clip,
                                                const CLIPRDR_FORMAT_DATA_REQUEST *request);
static UINT rdp_clip_server_format_data_response(CliprdrClientContext *clip,
                                                 const CLIPRDR_FORMAT_DATA_RESPONSE *response);
static UINT rdp_clip_lock(CliprdrClientContext *clip,
                          const CLIPRDR_LOCK_CLIPBOARD_DATA *lock);
static UINT rdp_clip_unlock(CliprdrClientContext *clip,
                            const CLIPRDR_UNLOCK_CLIPBOARD_DATA *unlock);
static UINT rdp_clip_file_request(CliprdrClientContext *clip,
                                  const CLIPRDR_FILE_CONTENTS_REQUEST *request);
static UINT rdp_clip_file_response(CliprdrClientContext *clip,
                                   const CLIPRDR_FILE_CONTENTS_RESPONSE *response);

static int rdp_verify_x509(freerdp *instance, const BYTE *data, size_t length,
                           const char *hostname, UINT16 port, DWORD flags);
static DWORD rdp_verify_certificate_ex(freerdp *instance, const char *host, UINT16 port,
                                       const char *common_name, const char *subject,
                                       const char *issuer, const char *fingerprint, DWORD flags);
static DWORD rdp_verify_changed_certificate_ex(freerdp *instance, const char *host, UINT16 port,
                                               const char *common_name, const char *subject,
                                               const char *issuer, const char *new_fingerprint,
                                               const char *old_subject, const char *old_issuer,
                                               const char *old_fingerprint, DWORD flags);
static BOOL rdp_authenticate(freerdp *instance, char **username, char **password, char **domain,
                             rdp_auth_reason reason);
static SSIZE_T rdp_retry_dialog(freerdp *instance, const char *what, size_t current, void *userarg);
static int rdp_logon_error_info(freerdp *instance, UINT32 data, UINT32 type);

static BOOL rdp_client_new(freerdp *instance, rdpContext *context)
{
    RDPMacContext *ctx = (RDPMacContext *)context;
    ctx->owner = nil;
    ctx->clipboard = nil;
    ctx->disp = NULL;

    instance->PreConnect = rdp_pre_connect;
    instance->PostConnect = rdp_post_connect;
    instance->PostDisconnect = rdp_post_disconnect;
    instance->VerifyX509Certificate = rdp_verify_x509;
    instance->VerifyCertificateEx = rdp_verify_certificate_ex;
    instance->VerifyChangedCertificateEx = rdp_verify_changed_certificate_ex;
    instance->AuthenticateEx = rdp_authenticate;
    instance->RetryDialog = rdp_retry_dialog;
    instance->LogonErrorInfo = rdp_logon_error_info;
    return TRUE;
}

static void rdp_client_free(freerdp *instance, rdpContext *context)
{
    (void)instance;
    RDPMacContext *ctx = (RDPMacContext *)context;
    ctx->owner = nil;
    ctx->clipboard = nil;
    ctx->disp = NULL;
}

static BOOL rdp_pre_connect(freerdp *instance)
{
    rdpContext *context = instance->context;
    rdpSettings *settings = context->settings;

    freerdp_settings_set_bool(settings, FreeRDP_CertificateCallbackPreferPEM, TRUE);
    freerdp_settings_set_uint32(settings, FreeRDP_OsMajorType, OSMAJORTYPE_UNIX);
    freerdp_settings_set_uint32(settings, FreeRDP_OsMinorType, OSMINORTYPE_NATIVE_XSERVER);

    if (PubSub_SubscribeChannelConnected(context->pubSub, rdp_channel_connected) < 0)
        return FALSE;
    if (PubSub_SubscribeChannelDisconnected(context->pubSub, rdp_channel_disconnected) < 0)
        return FALSE;
    return TRUE;
}

static BOOL rdp_begin_paint(rdpContext *context)
{
    if (!context || !context->gdi || !context->gdi->primary)
        return TRUE;
    HGDI_DC hdc = context->gdi->primary->hdc;
    if (hdc && hdc->hwnd && hdc->hwnd->invalid)
        hdc->hwnd->invalid->null = TRUE;
    return TRUE;
}

static BOOL rdp_end_paint(rdpContext *context)
{
    if (!context || !context->gdi)
        return TRUE;
    rdpGdi *gdi = context->gdi;
    if (!gdi->primary || !gdi->primary_buffer)
        return TRUE;
    HGDI_DC hdc = gdi->primary->hdc;
    if (!hdc || !hdc->hwnd || !hdc->hwnd->invalid)
        return TRUE;
    HGDI_RGN invalid = hdc->hwnd->invalid;
    if (invalid->null || invalid->w <= 0 || invalid->h <= 0)
        return TRUE;

    RDPMacClient *owner = RDPMacOwner(context);
    if (owner) {
        [owner copyFrameRegionFromBuffer:gdi->primary_buffer
                                  stride:(size_t)gdi->stride
                                       x:invalid->x
                                       y:invalid->y
                                   width:invalid->w
                                  height:invalid->h];
    }
    return TRUE;
}

static BOOL rdp_desktop_resize(rdpContext *context)
{
    if (!context || !context->gdi)
        return FALSE;
    rdpSettings *settings = context->settings;
    rdpGdi *gdi = context->gdi;
    const UINT32 width = freerdp_settings_get_uint32(settings, FreeRDP_DesktopWidth);
    const UINT32 height = freerdp_settings_get_uint32(settings, FreeRDP_DesktopHeight);
    if (!gdi_resize(gdi, width, height))
        return FALSE;

    RDPMacClient *owner = RDPMacOwner(context);
    if (owner)
        [owner framebufferDidResizeWidth:(size_t)gdi->width height:(size_t)gdi->height];
    return TRUE;
}

static BOOL rdp_play_sound(rdpContext *context, const PLAY_SOUND_UPDATE *playSound)
{
    (void)context;
    (void)playSound;
    return TRUE;
}

static BOOL rdp_keyboard_indicators(rdpContext *context, UINT16 ledFlags)
{
    (void)context;
    (void)ledFlags;
    return TRUE;
}

static BOOL rdp_keyboard_ime(rdpContext *context, UINT16 imeId, UINT32 imeState,
                             UINT32 imeConvMode)
{
    (void)context;
    (void)imeId;
    (void)imeState;
    (void)imeConvMode;
    return TRUE;
}

static BOOL rdp_post_connect(freerdp *instance)
{
    if (!gdi_init(instance, PIXEL_FORMAT_BGRX32))
        return FALSE;

    rdpContext *context = instance->context;
    rdpGdi *gdi = context->gdi;
    context->update->BeginPaint = rdp_begin_paint;
    context->update->EndPaint = rdp_end_paint;
    context->update->DesktopResize = rdp_desktop_resize;
    context->update->PlaySound = rdp_play_sound;
    context->update->SetKeyboardIndicators = rdp_keyboard_indicators;
    context->update->SetKeyboardImeStatus = rdp_keyboard_ime;

    RDPMacClient *owner = RDPMacOwner(context);
    if (!owner)
        return FALSE;
    [owner framebufferConfigureWithWidth:(size_t)gdi->width height:(size_t)gdi->height];
    return TRUE;
}

static void rdp_post_disconnect(freerdp *instance)
{
    rdpContext *context = instance->context;
    if (!context)
        return;

    PubSub_UnsubscribeChannelConnected(context->pubSub, rdp_channel_connected);
    PubSub_UnsubscribeChannelDisconnected(context->pubSub, rdp_channel_disconnected);

    RDPMacContext *ctx = (RDPMacContext *)context;
    ctx->disp = NULL;
    RDPMacClipboardController *clipboard = ctx->clipboard;

    if (context->gdi) {
        gdi_free(instance);
    }

    if (clipboard) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [clipboard handleChannelDisconnected];
        });
    }
}

static void rdp_channel_connected(void *context, const ChannelConnectedEventArgs *e)
{
    if (!context || !e || !e->name)
        return;
    rdpContext *rdp = (rdpContext *)context;
    RDPMacContext *ctx = (RDPMacContext *)rdp;

    if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) {
        CliprdrClientContext *clip = (CliprdrClientContext *)e->pInterface;
        if (!clip)
            return;
        clip->custom = (__bridge void *)ctx->owner;
        clip->MonitorReady = rdp_clip_monitor_ready;
        clip->ServerCapabilities = rdp_clip_server_capabilities;
        clip->ServerFormatList = rdp_clip_server_format_list;
        clip->ServerFormatListResponse = rdp_clip_server_format_list_response;
        clip->ServerFormatDataRequest = rdp_clip_server_format_data_request;
        clip->ServerFormatDataResponse = rdp_clip_server_format_data_response;
        clip->ServerLockClipboardData = rdp_clip_lock;
        clip->ServerUnlockClipboardData = rdp_clip_unlock;
        clip->ServerFileContentsRequest = rdp_clip_file_request;
        clip->ServerFileContentsResponse = rdp_clip_file_response;

        RDPMacClipboardController *controller = ctx->clipboard;
        if (controller) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller attachChannel:clip];
            });
        }
    } else if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0) {
        ctx->disp = (DispClientContext *)e->pInterface;
        RDPMacClient *owner = ctx->owner;
        dispatch_async(dispatch_get_main_queue(), ^{
            [owner logMessage:@"DisplayControl: канал изменения разрешения подключён" level:0];
        });
    }
}

static void rdp_channel_disconnected(void *context, const ChannelDisconnectedEventArgs *e)
{
    if (!context || !e || !e->name)
        return;
    rdpContext *rdp = (rdpContext *)context;
    RDPMacContext *ctx = (RDPMacContext *)rdp;

    if (strcmp(e->name, CLIPRDR_SVC_CHANNEL_NAME) == 0) {
        RDPMacClipboardController *controller = ctx->clipboard;
        if (controller) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [controller handleChannelDisconnected];
            });
        }
    } else if (strcmp(e->name, DISP_DVC_CHANNEL_NAME) == 0) {
        ctx->disp = NULL;
    }
}

static UINT rdp_clip_monitor_ready(CliprdrClientContext *clip,
                                   const CLIPRDR_MONITOR_READY *monitorReady)
{
    (void)monitorReady;
    if (!clip)
        return CHANNEL_RC_BAD_INIT_HANDLE;
    RDPMacClient *owner = (__bridge RDPMacClient *)clip->custom;
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner clipboardThreadMonitorReady];
    });
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_server_capabilities(CliprdrClientContext *clip,
                                         const CLIPRDR_CAPABILITIES *capabilities)
{
    if (!clip || !capabilities)
        return CHANNEL_RC_BAD_INIT_HANDLE;
    uint32_t version = 0;
    uint32_t flags = 0;
    BOOL found = NO;
    for (UINT32 i = 0; i < capabilities->cCapabilitiesSets; i++) {
        const CLIPRDR_CAPABILITY_SET *set = &capabilities->capabilitySets[i];
        if (set->capabilitySetType == CB_CAPSTYPE_GENERAL &&
            set->capabilitySetLength >= CB_CAPSTYPE_GENERAL_LEN) {
            const CLIPRDR_GENERAL_CAPABILITY_SET *general =
                (const CLIPRDR_GENERAL_CAPABILITY_SET *)set;
            version = general->version;
            flags = general->generalFlags;
            found = YES;
            break;
        }
    }
    if (found) {
        RDPMacClient *owner = (__bridge RDPMacClient *)clip->custom;
        dispatch_async(dispatch_get_main_queue(), ^{
            [owner clipboardThreadCapabilities:flags version:version];
        });
    }
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_server_format_list(CliprdrClientContext *clip,
                                        const CLIPRDR_FORMAT_LIST *formatList)
{
    if (!clip || !formatList)
        return CHANNEL_RC_BAD_INIT_HANDLE;

    NSMutableArray<NSNumber *> *ids = [NSMutableArray arrayWithCapacity:formatList->numFormats];
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:formatList->numFormats];
    for (UINT32 i = 0; i < formatList->numFormats; i++) {
        const CLIPRDR_FORMAT *format = &formatList->formats[i];
        [ids addObject:@(format->formatId)];
        NSString *name = nil;
        if (format->formatName && format->formatName[0] != '\0')
            name = [NSString stringWithUTF8String:format->formatName];
        if (name.length == 0)
            name = RDPMacClipboardFormatName(format->formatId);
        [names addObject:name];
    }

    RDPMacClient *owner = (__bridge RDPMacClient *)clip->custom;
    NSArray *idsCopy = [ids copy];
    NSArray *namesCopy = [names copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner clipboardThreadFormatList:idsCopy names:namesCopy];
    });
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_server_format_list_response(CliprdrClientContext *clip,
                                                 const CLIPRDR_FORMAT_LIST_RESPONSE *response)
{
    if (!clip || !response)
        return CHANNEL_RC_BAD_INIT_HANDLE;
    RDPMacClient *owner = (__bridge RDPMacClient *)clip->custom;
    const uint16_t flags = response->common.msgFlags;
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner clipboardThreadFormatListResponse:flags];
    });
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_server_format_data_request(CliprdrClientContext *clip,
                                                const CLIPRDR_FORMAT_DATA_REQUEST *request)
{
    if (!clip || !request)
        return CHANNEL_RC_BAD_INIT_HANDLE;
    RDPMacClient *owner = (__bridge RDPMacClient *)clip->custom;
    const uint32_t formatId = request->requestedFormatId;
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner clipboardThreadFormatDataRequest:formatId];
    });
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_server_format_data_response(CliprdrClientContext *clip,
                                                 const CLIPRDR_FORMAT_DATA_RESPONSE *response)
{
    if (!clip || !response)
        return CHANNEL_RC_BAD_INIT_HANDLE;
    NSData *data = [NSData data];
    if (response->requestedFormatData && response->common.dataLen > 0)
        data = [NSData dataWithBytes:response->requestedFormatData length:response->common.dataLen];
    const uint16_t flags = response->common.msgFlags;
    RDPMacClient *owner = (__bridge RDPMacClient *)clip->custom;
    dispatch_async(dispatch_get_main_queue(), ^{
        [owner clipboardThreadFormatDataResponse:data flags:flags];
    });
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_lock(CliprdrClientContext *clip, const CLIPRDR_LOCK_CLIPBOARD_DATA *lock)
{
    (void)clip;
    (void)lock;
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_unlock(CliprdrClientContext *clip, const CLIPRDR_UNLOCK_CLIPBOARD_DATA *unlock)
{
    (void)clip;
    (void)unlock;
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_file_request(CliprdrClientContext *clip,
                                  const CLIPRDR_FILE_CONTENTS_REQUEST *request)
{
    (void)clip;
    (void)request;
    return CHANNEL_RC_OK;
}

static UINT rdp_clip_file_response(CliprdrClientContext *clip,
                                   const CLIPRDR_FILE_CONTENTS_RESPONSE *response)
{
    (void)clip;
    (void)response;
    return CHANNEL_RC_OK;
}

static BOOL rdp_authenticate(freerdp *instance, char **username, char **password, char **domain,
                             rdp_auth_reason reason)
{
    (void)instance;
    (void)username;
    (void)password;
    (void)domain;
    (void)reason;
    // Credentials are set in rdpSettings before connect; never prompt on stdin.
    return TRUE;
}

static SSIZE_T rdp_retry_dialog(freerdp *instance, const char *what, size_t current, void *userarg)
{
    (void)instance;
    (void)what;
    (void)current;
    (void)userarg;
    // No automatic reconnect loops; the UI offers an explicit retry button.
    return -1;
}

static int rdp_logon_error_info(freerdp *instance, UINT32 data, UINT32 type)
{
    RDPMacClient *owner = RDPMacOwner(instance ? instance->context : NULL);
    const char *dataText = freerdp_get_logon_error_info_data(data);
    const char *typeText = freerdp_get_logon_error_info_type(type);
    NSString *message = [NSString stringWithFormat:@"Сервер: %s (%s)",
                                                   dataText ? dataText : "—",
                                                   typeText ? typeText : "—"];
    [owner logMessage:message level:2];
    return 1;
}

static int RDPMacClientEntry(RDP_CLIENT_ENTRY_POINTS *pEntryPoints)
{
    ZeroMemory(pEntryPoints, sizeof(*pEntryPoints));
    pEntryPoints->Version = RDP_CLIENT_INTERFACE_VERSION;
    pEntryPoints->Size = (DWORD)sizeof(*pEntryPoints);
    pEntryPoints->GlobalInit = rdp_client_global_init;
    pEntryPoints->GlobalUninit = rdp_client_global_uninit;
    pEntryPoints->ContextSize = (DWORD)sizeof(RDPMacContext);
    pEntryPoints->ClientNew = rdp_client_new;
    pEntryPoints->ClientFree = rdp_client_free;
    pEntryPoints->ClientStart = rdp_client_start;
    pEntryPoints->ClientStop = rdp_client_stop;
    return 0;
}

static int rdp_verify_x509(freerdp *instance, const BYTE *data, size_t length,
                           const char *hostname, UINT16 port, DWORD flags)
{
    RDPMacClient *owner = RDPMacOwner(instance ? instance->context : NULL);
    if (!owner || !data || length == 0)
        return 0;
    NSData *pem = [NSData dataWithBytes:data length:length];
    NSString *host = hostname ? [NSString stringWithUTF8String:hostname] : @"";
    const BOOL changed = (flags & VERIFY_CERT_FLAG_CHANGED) != 0;
    const int decision = [owner certificateDecisionForPEM:pem
                                                 hostname:host
                                                     port:(NSInteger)port
                                                  changed:changed];
    if (decision == 2)
        return 2; // accept once
    if (decision == 1)
        return 1; // accept and remember
    return 0;
}

static DWORD rdp_verify_certificate_ex(freerdp *instance, const char *host, UINT16 port,
                                       const char *common_name, const char *subject,
                                       const char *issuer, const char *fingerprint, DWORD flags)
{
    (void)common_name;
    RDPMacClient *owner = RDPMacOwner(instance ? instance->context : NULL);
    if (!owner)
        return 0;
    NSString *hostString = host ? [NSString stringWithUTF8String:host] : @"";
    NSString *subjectString = subject ? [NSString stringWithUTF8String:subject] : @"—";
    NSString *issuerString = issuer ? [NSString stringWithUTF8String:issuer] : @"—";
    NSString *fingerprintString =
        fingerprint ? [NSString stringWithUTF8String:fingerprint] : @"—";
    const BOOL changed = (flags & VERIFY_CERT_FLAG_CHANGED) != 0;
    const int decision = [owner certificateDecisionWithSubject:subjectString
                                                        issuer:issuerString
                                                   fingerprint:fingerprintString
                                                      hostname:hostString
                                                          port:(NSInteger)port
                                                       changed:changed];
    return (DWORD)decision;
}

static DWORD rdp_verify_changed_certificate_ex(freerdp *instance, const char *host, UINT16 port,
                                               const char *common_name, const char *subject,
                                               const char *issuer, const char *new_fingerprint,
                                               const char *old_subject, const char *old_issuer,
                                               const char *old_fingerprint, DWORD flags)
{
    (void)common_name;
    (void)old_subject;
    (void)flags;
    RDPMacClient *owner = RDPMacOwner(instance ? instance->context : NULL);
    if (!owner)
        return 0;
    NSString *hostString = host ? [NSString stringWithUTF8String:host] : @"";
    NSString *subjectString = subject ? [NSString stringWithUTF8String:subject] : @"—";
    NSString *issuerString = issuer ? [NSString stringWithUTF8String:issuer] : @"—";
    NSString *fingerprintString =
        new_fingerprint ? [NSString stringWithUTF8String:new_fingerprint] : @"—";
    [owner logMessage:[NSString stringWithFormat:@"TLS: сертификат изменился. Старый издатель: %s, "
                                                @"старый отпечаток: %s",
                                                old_issuer ? old_issuer : "—",
                                                old_fingerprint ? old_fingerprint : "—"]
                level:1];
    const int decision = [owner certificateDecisionWithSubject:subjectString
                                                        issuer:issuerString
                                                   fingerprint:fingerprintString
                                                      hostname:hostString
                                                          port:(NSInteger)port
                                                       changed:YES];
    return (DWORD)decision;
}

@implementation RDPMacClient
{
    RDPMacContext *_context;
    NSThread *_thread;
    dispatch_semaphore_t _threadFinished;
    pthread_mutex_t _apiLock;
    volatile BOOL _stopRequested;
    volatile BOOL _deallocating;

    RDPMacClipboardController *_clipboard;
    BOOL _clipboardEnabled;
    BOOL _commandAsControl;
    NSTimeInterval _certificateTimeout;

    pthread_mutex_t _frameLock;
    uint8_t *_frame;
    size_t _frameCapacity;
    size_t _frameWidth;
    size_t _frameHeight;
    size_t _frameStride;
    BOOL _hasFrame;
    CGRect _dirtyRect;
    BOOL _dirtyValid;
    BOOL _invalidateScheduled;

    NSEventModifierFlags _sentModifiers;
    NSMutableSet<NSNumber *> *_unicodeKeys;
    BOOL _capsLockState;
    double _wheelAccumulatorY;
    double _wheelAccumulatorX;

    dispatch_semaphore_t _certificateSemaphore;
    BOOL _certificatePromptActive;
    BOOL _certificateRejected;
}

+ (void)initialize
{
    if (self == [RDPMacClient class]) {
        freerdp_setApplicationDetails(FREERDP_VENDOR_STRING, "RDPMac", FREERDP_VERSION_MAJOR);
    }
}

+ (NSString *)selfTestReport
{
    NSMutableString *report = [NSMutableString string];
    [report appendFormat:@"FreeRDP %s (WinPR %s, architecture %s)\n", FREERDP_VERSION,
                           WINPR_VERSION, sizeof(void *) == 8 ? "64-bit" : "32-bit"];

    RDP_CLIENT_ENTRY_POINTS entryPoints = {0};
    if (RDPMacClientEntry(&entryPoints) != 0)
        return @"FAIL: RDP client entry points";
    rdpContext *context = freerdp_client_context_new(&entryPoints);
    if (!context)
        return @"FAIL: freerdp_client_context_new";
    freerdp_client_context_free(context);
    [report appendString:@"context create/free: OK\n"];

    NSString *sample = @"Привет, мир!\nHello world\n🚀 Emoji & Юникод";
    NSError *error = nil;
    NSData *unicode = RDPMacClipboardEncodeText(sample, RDPMacClipboardFormatUnicodeText, &error);
    NSString *unicodeBack = unicode
        ? RDPMacClipboardDecodeText(unicode, RDPMacClipboardFormatUnicodeText)
        : nil;
    if (![unicodeBack isEqualToString:sample])
        return [NSString stringWithFormat:@"FAIL: unicode roundtrip (%@)",
                                          error.localizedDescription ?: @"mismatch"];
    [report appendFormat:@"clipboard UTF-16LE: OK (%lu bytes)\n", (unsigned long)unicode.length];

    NSString *cyrillic = @"Проверка CF_TEXT: привет";
    NSData *ansi = RDPMacClipboardEncodeText(cyrillic, RDPMacClipboardFormatText, &error);
    NSString *ansiBack = ansi ? RDPMacClipboardDecodeText(ansi, RDPMacClipboardFormatText) : nil;
    if (![ansiBack isEqualToString:cyrillic])
        return @"FAIL: CF_TEXT roundtrip";
    [report appendString:@"clipboard CF_TEXT: OK\n"];
    [report appendString:@"RESULT: OK\n"];
    return report;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        pthread_mutex_init(&_apiLock, NULL);
        pthread_mutex_init(&_frameLock, NULL);
        _unicodeKeys = [NSMutableSet set];
        _certificateTimeout = 180.0;
        _clipboard = [[RDPMacClipboardController alloc] initWithEnabled:NO];
        _clipboard.client = self;
        _state = RDPMacConnectionStateIdle;
    }
    return self;
}

- (void)dealloc
{
    _deallocating = YES;
    [self disconnect];
    if (_thread && !_thread.isFinished && _threadFinished) {
        dispatch_semaphore_wait(_threadFinished,
                                dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)));
    }
    [self rejectPendingCertificatePrompt];
    [_clipboard shutdown];

    pthread_mutex_lock(&_frameLock);
    free(_frame);
    _frame = NULL;
    pthread_mutex_unlock(&_frameLock);
    pthread_mutex_destroy(&_frameLock);
    pthread_mutex_destroy(&_apiLock);
}

- (BOOL)isSessionUsable
{
    return _state == RDPMacConnectionStateConnected && _context != NULL;
}

- (void)logMessage:(NSString *)message level:(NSInteger)level
{
    // FreeRDP callbacks run on the connection thread; the delegate contract is
    // main-thread only (LogStore and the UI are not thread-safe).
    void (^deliver)(void) = ^{
        if (self->_deallocating)
            return;
        id<RDPMacClientDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(rdpClient:didLogMessage:level:)])
            [delegate rdpClient:self didLogMessage:message level:level];
    };
    if ([NSThread isMainThread])
        deliver();
    else
        dispatch_async(dispatch_get_main_queue(), deliver);
}

- (void)setState:(RDPMacConnectionState)state message:(NSString *)message
{
    _state = state;
    id<RDPMacClientDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(rdpClient:didChangeState:message:)])
        [delegate rdpClient:self didChangeState:state message:message];
}

static NSError *RDPMacClientError(NSString *message)
{
    return [NSError errorWithDomain:RDPMacErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : message}];
}

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
 certificatePromptTimeout:(NSTimeInterval)timeout
                 error:(NSError **)error
{
    NSString *trimmedHost = [host stringByTrimmingCharactersInSet:
                                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedHost.length == 0) {
        if (error)
            *error = RDPMacClientError(@"Укажите адрес сервера.");
        return NO;
    }
    if (port < 1 || port > 65535) {
        if (error)
            *error = RDPMacClientError(@"Порт должен быть в диапазоне 1–65535.");
        return NO;
    }
    if (_thread && !_thread.isFinished) {
        if (error)
            *error = RDPMacClientError(@"Предыдущее подключение ещё завершается. Подождите.");
        return NO;
    }
    if (_context) {
        if (error)
            *error = RDPMacClientError(@"Внутренняя ошибка: предыдущий сеанс не освобождён.");
        return NO;
    }

    NSUInteger safeWidth = MAX((NSUInteger)640, MIN(width, RDPMacMaxFrameDimension));
    NSUInteger safeHeight = MAX((NSUInteger)480, MIN(height, RDPMacMaxFrameDimension));
    safeWidth &= ~(NSUInteger)1;
    safeHeight &= ~(NSUInteger)1;

    _stopRequested = NO;
    _certificateRejected = NO;
    _clipboardEnabled = clipboardEnabled;
    _commandAsControl = commandAsControl;
    _certificateTimeout = MAX(10.0, MIN(timeout, 600.0));
    _sentModifiers = 0;
    _capsLockState = NO;
    [_unicodeKeys removeAllObjects];

    [_clipboard shutdown];
    _clipboard = [[RDPMacClipboardController alloc] initWithEnabled:clipboardEnabled];
    _clipboard.client = self;

    pthread_mutex_lock(&_frameLock);
    _hasFrame = NO;
    _dirtyValid = NO;
    _dirtyRect = CGRectZero;
    _invalidateScheduled = NO;
    pthread_mutex_unlock(&_frameLock);

    RDP_CLIENT_ENTRY_POINTS entryPoints = {0};
    if (RDPMacClientEntry(&entryPoints) != 0) {
        if (error)
            *error = RDPMacClientError(@"Не удалось инициализировать FreeRDP.");
        return NO;
    }

    rdpContext *context = freerdp_client_context_new(&entryPoints);
    if (!context) {
        if (error)
            *error = RDPMacClientError(@"Не удалось создать контекст FreeRDP.");
        return NO;
    }

    RDPMacContext *macContext = (RDPMacContext *)context;
    macContext->owner = self;
    macContext->clipboard = _clipboard;
    macContext->disp = NULL;

    rdpSettings *settings = context->settings;
    BOOL ok = YES;
    ok = ok &&
         freerdp_settings_set_string(settings, FreeRDP_ServerHostname, trimmedHost.UTF8String);
    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_ServerPort, (UINT32)port);
    ok = ok && freerdp_settings_set_string(settings, FreeRDP_Username, username.UTF8String ?: "");
    ok = ok && freerdp_settings_set_string(settings, FreeRDP_Domain, domain.UTF8String ?: "");
    ok = ok && freerdp_settings_set_string(settings, FreeRDP_Password, password.UTF8String ?: "");
    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, (UINT32)safeWidth);
    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, (UINT32)safeHeight);
    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, 32);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_UseCommonStdioCallbacks, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_AuthenticationOnly, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_AutoAcceptCertificate, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_AutoDenyCertificate, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_CertificateCallbackPreferPEM, TRUE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectClipboard, clipboardEnabled);
    ok = ok && freerdp_settings_set_uint32(settings, FreeRDP_ClipboardFeatureMask,
                                           CLIPRDR_FLAG_LOCAL_TO_REMOTE |
                                               CLIPRDR_FLAG_REMOTE_TO_LOCAL);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SupportDisplayControl, TRUE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_DesktopResize, TRUE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_AudioPlayback, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectDrives, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectPrinters, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectSerialPorts, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectSmartCards, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_DeviceRedirection, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectHomeDrive, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectParallelPorts, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RedirectWebAuthN, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_EncomspVirtualChannel, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RemoteApplicationMode, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SupportGraphicsPipeline, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SupportGeometryTracking, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SupportEchoChannel, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SupportVideoOptimized, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SupportSSHAgentChannel, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_MultiTouchInput, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_AudioCapture, FALSE);
    // These RDP8 features implicitly require the rdpdr channel, which is not
    // built in this minimal client. Disable them explicitly.
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_NetworkAutoDetect, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SupportHeartbeatPdu, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_SupportMultitransport, FALSE);
    ok = ok && freerdp_settings_set_bool(settings, FreeRDP_NegotiateSecurityLayer, TRUE);
    switch (securityMode) {
        case RDPMacSecurityModeTLS:
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, FALSE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, FALSE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_UseRdpSecurityLayer, FALSE);
            break;
        case RDPMacSecurityModeLegacyRDP:
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, FALSE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, FALSE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_UseRdpSecurityLayer, TRUE);
            break;
        case RDPMacSecurityModeNegotiate:
        default:
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, TRUE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, FALSE);
            ok = ok && freerdp_settings_set_bool(settings, FreeRDP_UseRdpSecurityLayer, FALSE);
            break;
    }

    if (!ok) {
        freerdp_client_context_free(context);
        if (error)
            *error = RDPMacClientError(@"Не удалось применить параметры подключения.");
        return NO;
    }

    _context = macContext;
    _threadFinished = dispatch_semaphore_create(0);
    [self setState:RDPMacConnectionStateConnecting
            message:[NSString stringWithFormat:@"Подключение к %@:%ld…", trimmedHost, (long)port]];
    [self logMessage:[NSString stringWithFormat:@"Подключение: %@:%ld, пользователь %@, домен %@, "
                                                @"режим безопасности %ld, размер %lux%lu",
                                                trimmedHost, (long)port,
                                                username.length ? username : @"(пусто)",
                                                domain.length ? domain : @"(пусто)",
                                                (long)securityMode, (unsigned long)safeWidth,
                                                (unsigned long)safeHeight]
                level:0];

    _thread = [[NSThread alloc] initWithTarget:self
                                      selector:@selector(connectionThreadMain)
                                        object:nil];
    _thread.name = @"RDPMac.Connection";
    _thread.qualityOfService = NSQualityOfServiceUserInitiated;
    [_thread start];
    return YES;
}

- (void)rejectPendingCertificatePrompt
{
    dispatch_semaphore_t semaphore = nil;
    pthread_mutex_lock(&_apiLock);
    if (_certificatePromptActive && _certificateSemaphore) {
        semaphore = _certificateSemaphore;
        _certificatePromptActive = NO;
    }
    pthread_mutex_unlock(&_apiLock);
    if (semaphore)
        dispatch_semaphore_signal(semaphore);
}

- (void)disconnect
{
    pthread_mutex_lock(&_apiLock);
    if (_state == RDPMacConnectionStateIdle || _state == RDPMacConnectionStateDisconnected ||
        _state == RDPMacConnectionStateFailed) {
        pthread_mutex_unlock(&_apiLock);
        return;
    }
    _stopRequested = YES;
    pthread_mutex_unlock(&_apiLock);

    [self rejectPendingCertificatePrompt];
    [self setState:RDPMacConnectionStateDisconnecting message:@"Отключение…"];
    [self logMessage:@"Запрошено отключение" level:0];

    pthread_mutex_lock(&_apiLock);
    rdpContext *context = _context ? &_context->common.context : NULL;
    if (context)
        freerdp_abort_connect_context(context);
    pthread_mutex_unlock(&_apiLock);

    [_clipboard handleChannelDisconnected];
}

- (void)connectionThreadMain
{
    @autoreleasepool {
        pthread_mutex_lock(&_apiLock);
        rdpContext *context = _context ? &_context->common.context : NULL;
        freerdp *instance = context ? context->instance : NULL;
        pthread_mutex_unlock(&_apiLock);

        if (!instance) {
            [self finishSessionWithContext:NULL error:@"Внутренняя ошибка: нет контекста FreeRDP"];
            return;
        }

        BOOL connected = freerdp_connect(instance);
        UINT32 errorCode = connected ? FREERDP_ERROR_SUCCESS : freerdp_get_last_error(instance->context);
        if (!connected) {
            NSString *message = _certificateRejected
                                    ? @"Сертификат сервера отклонён. Подключение отменено."
                                    : RDPMacErrorText(errorCode);
            [self logMessage:[NSString stringWithFormat:@"Ошибка подключения: %@", message] level:2];
            freerdp_disconnect(instance);
            [self finishSessionWithContext:instance->context error:message];
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self setState:RDPMacConnectionStateConnected message:@"Подключено"];
            id<RDPMacClientDelegate> delegate = self.delegate;
            if ([delegate respondsToSelector:@selector(rdpClientDidConnect:)])
                [delegate rdpClientDidConnect:self];
            [self notifyClipboardDiagnostics];
        });

        while (!_stopRequested && !freerdp_shall_disconnect_context(instance->context)) {
            HANDLE handles[MAXIMUM_WAIT_OBJECTS] = {0};
            DWORD count = freerdp_get_event_handles(instance->context, handles,
                                                    MAXIMUM_WAIT_OBJECTS);
            if (count == 0) {
                errorCode = freerdp_get_last_error(instance->context);
                [self logMessage:@"Основной цикл: не удалось получить события FreeRDP" level:2];
                break;
            }

            DWORD status = WaitForMultipleObjects(count, handles, FALSE, 500);
            if (status == WAIT_FAILED) {
                errorCode = freerdp_get_last_error(instance->context);
                [self logMessage:@"Основной цикл: WaitForMultipleObjects завершился ошибкой" level:2];
                break;
            }
            if (!freerdp_check_event_handles(instance->context)) {
                errorCode = freerdp_get_last_error(instance->context);
                if (errorCode == FREERDP_ERROR_SUCCESS)
                    [self logMessage:@"Основной цикл: обработка событий FreeRDP не удалась" level:2];
                break;
            }
        }

        errorCode = freerdp_get_last_error(instance->context);
        [self logMessage:@"Отключение сеанса RDP" level:0];
        freerdp_disconnect(instance);

        NSString *message = nil;
        if (!_stopRequested && errorCode != FREERDP_ERROR_SUCCESS &&
            errorCode != FREERDP_ERROR_CONNECT_CANCELLED) {
            const UINT32 errorClass = GET_FREERDP_ERROR_CLASS(errorCode);
            if (errorClass != FREERDP_ERROR_ERRINFO_CLASS)
                message = RDPMacErrorText(errorCode);
        }
        [self finishSessionWithContext:instance->context error:message];
    }
}

- (void)finishSessionWithContext:(rdpContext *)context error:(NSString *)error
{
    // The CLIPRDR context is owned by FreeRDP; drop the pointer before freeing
    // it so a clipboard timer or UI action cannot call into freed memory.
    [_clipboard invalidateChannel];
    RDPMacContext *macContext = _context;
    if (macContext) {
        pthread_mutex_lock(&_apiLock);
        if (_context == macContext)
            _context = NULL;
        pthread_mutex_unlock(&_apiLock);
        freerdp_client_context_free(&macContext->common.context);
    }
    if (_threadFinished)
        dispatch_semaphore_signal(_threadFinished);

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_clipboard handleChannelDisconnected];
        self->_thread = nil;
        if (error.length > 0) {
            self->_lastErrorText = [error copy];
            [self setState:RDPMacConnectionStateFailed message:error];
            [self logMessage:error level:2];
        } else {
            self->_lastErrorText = nil;
            [self setState:RDPMacConnectionStateDisconnected message:@"Сеанс завершён"];
        }
        if (self->_deallocating)
            return;
        id<RDPMacClientDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(rdpClient:didDisconnectWithError:)])
            [delegate rdpClient:self didDisconnectWithError:error];
        [self notifyClipboardDiagnostics];
    });
}

- (int)certificateDecisionForPEM:(NSData *)pem
                        hostname:(NSString *)hostname
                            port:(NSInteger)port
                         changed:(BOOL)changed
{
    RDPMacCertificateInfo *info = RDPMacCertificateInfoFromPEM(pem, hostname, port, changed);
    return [self decisionForCertificateInfo:info];
}

- (int)certificateDecisionWithSubject:(NSString *)subject
                               issuer:(NSString *)issuer
                          fingerprint:(NSString *)fingerprint
                             hostname:(NSString *)hostname
                                 port:(NSInteger)port
                              changed:(BOOL)changed
{
    RDPMacCertificateInfo *info = [[RDPMacCertificateInfo alloc] init];
    info.hostname = hostname;
    info.port = port;
    info.subject = subject.length ? subject : @"—";
    info.issuer = issuer.length ? issuer : @"—";
    info.fingerprintSHA256 = fingerprint.length ? fingerprint : @"—";
    info.changed = changed;
    info.details = [NSString stringWithFormat:@"Сервер: %@:%ld\nСубъект: %@\nИздатель: %@\n"
                                              @"Отпечаток: %@\nСертификат изменён: %@",
                                              hostname, (long)port, info.subject, info.issuer,
                                              info.fingerprintSHA256, changed ? @"да" : @"нет"];
    return [self decisionForCertificateInfo:info];
}

- (int)decisionForCertificateInfo:(RDPMacCertificateInfo *)info
{
    if (_stopRequested || _deallocating) {
        _certificateRejected = YES;
        return 0;
    }

    [self logMessage:[NSString stringWithFormat:@"TLS: требуется подтверждение сертификата %@:%ld "
                                                @"(SHA-256 %@)",
                                                info.hostname, (long)info.port,
                                                info.fingerprintSHA256]
                level:1];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block RDPMacCertificateDecision decision = RDPMacCertificateDecisionReject;

    pthread_mutex_lock(&_apiLock);
    _certificateSemaphore = semaphore;
    _certificatePromptActive = YES;
    pthread_mutex_unlock(&_apiLock);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_stopRequested) {
            dispatch_semaphore_signal(semaphore);
            return;
        }
        id<RDPMacClientDelegate> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(rdpClient:
                                                          didRequestCertificateApproval:
                                                                                 completion:)]) {
            [delegate rdpClient:self
                didRequestCertificateApproval:info
                                   completion:^(RDPMacCertificateDecision chosen) {
                                       decision = chosen;
                                       dispatch_semaphore_signal(semaphore);
                                   }];
        } else {
            [self logMessage:@"Нет обработчика подтверждения сертификата — отказ" level:2];
            dispatch_semaphore_signal(semaphore);
        }
    });

    const long waitResult =
        dispatch_semaphore_wait(semaphore,
                                dispatch_time(DISPATCH_TIME_NOW,
                                              (int64_t)(_certificateTimeout * NSEC_PER_SEC)));

    pthread_mutex_lock(&_apiLock);
    _certificatePromptActive = NO;
    _certificateSemaphore = nil;
    pthread_mutex_unlock(&_apiLock);

    if (waitResult != 0) {
        _certificateRejected = YES;
        [self logMessage:@"Истекло время ожидания подтверждения сертификата — отказ" level:2];
        return 0;
    }

    switch (decision) {
        case RDPMacCertificateDecisionAcceptAndRemember:
            [self logMessage:@"Сертификат принят и сохранён для этого сервера" level:1];
            return 1;
        case RDPMacCertificateDecisionAcceptOnce:
            [self logMessage:@"Сертификат принят только для текущего сеанса" level:1];
            return 2;
        case RDPMacCertificateDecisionReject:
        default:
            _certificateRejected = YES;
            [self logMessage:@"Сертификат отклонён пользователем" level:1];
            return 0;
    }
}

- (void)allocateFrameWithWidth:(size_t)width height:(size_t)height
{
    if (width == 0 || height == 0 || width > RDPMacMaxFrameDimension ||
        height > RDPMacMaxFrameDimension)
        return;

    const size_t stride = width * 4;
    const size_t needed = stride * height;
    if (needed == 0)
        return;

    pthread_mutex_lock(&_frameLock);
    if (needed > _frameCapacity) {
        uint8_t *newFrame = (uint8_t *)realloc(_frame, needed);
        if (!newFrame) {
            pthread_mutex_unlock(&_frameLock);
            [self logMessage:@"Недостаточно памяти для буфера кадра" level:2];
            return;
        }
        _frame = newFrame;
        _frameCapacity = needed;
    }
    if (_frame)
        memset(_frame, 0, needed);
    _frameWidth = width;
    _frameHeight = height;
    _frameStride = stride;
    _hasFrame = YES;
    _dirtyRect = CGRectMake(0, 0, (CGFloat)width, (CGFloat)height);
    _dirtyValid = YES;
    pthread_mutex_unlock(&_frameLock);
}

- (void)notifyFrameUpdatedWithResize:(BOOL)resize
{
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect dirty = CGRectZero;
        pthread_mutex_lock(&self->_frameLock);
        if (self->_dirtyValid)
            dirty = self->_dirtyRect;
        self->_dirtyValid = NO;
        self->_dirtyRect = CGRectZero;
        self->_invalidateScheduled = NO;
        const size_t width = self->_frameWidth;
        const size_t height = self->_frameHeight;
        pthread_mutex_unlock(&self->_frameLock);

        id<RDPMacClientDelegate> delegate = self.delegate;
        if (resize && [delegate respondsToSelector:@selector(rdpClient:didResizeToWidth:height:)])
            [delegate rdpClient:self didResizeToWidth:width height:height];
        if ([delegate respondsToSelector:@selector(rdpClient:didUpdateFrameInRect:)])
            [delegate rdpClient:self didUpdateFrameInRect:dirty];
    });
}

- (void)framebufferConfigureWithWidth:(size_t)width height:(size_t)height
{
    [self allocateFrameWithWidth:width height:height];
    [self logMessage:[NSString stringWithFormat:@"Удалённый рабочий стол: %lux%lu, формат BGRX32",
                                                (unsigned long)width, (unsigned long)height]
                level:0];
    [self notifyFrameUpdatedWithResize:YES];
}

- (void)framebufferDidResizeWidth:(size_t)width height:(size_t)height
{
    [self allocateFrameWithWidth:width height:height];
    [self logMessage:[NSString stringWithFormat:@"Размер удалённого рабочего стола изменён: %lux%lu",
                                                (unsigned long)width, (unsigned long)height]
                level:0];
    [self notifyFrameUpdatedWithResize:YES];
}

- (void)copyFrameRegionFromBuffer:(const uint8_t *)buffer
                           stride:(size_t)stride
                                x:(int32_t)x
                                y:(int32_t)y
                            width:(int32_t)width
                           height:(int32_t)height
{
    if (!buffer || width <= 0 || height <= 0 || x < 0 || y < 0)
        return;

    BOOL schedule = NO;
    pthread_mutex_lock(&_frameLock);
    if (_hasFrame && _frame) {
        int32_t copyWidth = width;
        int32_t copyHeight = height;
        if (x + copyWidth > (int32_t)_frameWidth)
            copyWidth = (int32_t)_frameWidth - x;
        if (y + copyHeight > (int32_t)_frameHeight)
            copyHeight = (int32_t)_frameHeight - y;
        if (copyWidth > 0 && copyHeight > 0) {
            for (int32_t row = 0; row < copyHeight; row++) {
                const uint8_t *src = buffer + (size_t)(y + row) * stride + (size_t)x * 4;
                uint8_t *dst = _frame + (size_t)(y + row) * _frameStride + (size_t)x * 4;
                memcpy(dst, src, (size_t)copyWidth * 4);
            }
            const CGRect region = CGRectMake(x, y, copyWidth, copyHeight);
            _dirtyRect = _dirtyValid ? CGRectUnion(_dirtyRect, region) : region;
            _dirtyValid = YES;
            if (!_invalidateScheduled) {
                _invalidateScheduled = YES;
                schedule = YES;
            }
        }
    }
    pthread_mutex_unlock(&_frameLock);

    if (schedule)
        [self notifyFrameUpdatedWithResize:NO];
}

- (BOOL)copyFrameIntoBuffer:(void *)dst
                     stride:(size_t)stride
                      width:(size_t *)width
                     height:(size_t *)height
{
    if (!dst)
        return NO;
    pthread_mutex_lock(&_frameLock);
    if (!_hasFrame || !_frame) {
        pthread_mutex_unlock(&_frameLock);
        return NO;
    }
    const size_t rowBytes = _frameWidth * 4;
    if (stride < rowBytes) {
        pthread_mutex_unlock(&_frameLock);
        return NO;
    }
    for (size_t row = 0; row < _frameHeight; row++) {
        memcpy((uint8_t *)dst + row * stride, _frame + row * _frameStride, rowBytes);
    }
    if (width)
        *width = _frameWidth;
    if (height)
        *height = _frameHeight;
    pthread_mutex_unlock(&_frameLock);
    return YES;
}

- (CGRect)takeDirtyRect
{
    CGRect result = CGRectZero;
    pthread_mutex_lock(&_frameLock);
    if (_dirtyValid) {
        result = _dirtyRect;
        _dirtyRect = CGRectZero;
        _dirtyValid = NO;
    }
    pthread_mutex_unlock(&_frameLock);
    return result;
}

- (size_t)frameWidth
{
    pthread_mutex_lock(&_frameLock);
    const size_t value = _frameWidth;
    pthread_mutex_unlock(&_frameLock);
    return value;
}

- (size_t)frameHeight
{
    pthread_mutex_lock(&_frameLock);
    const size_t value = _frameHeight;
    pthread_mutex_unlock(&_frameLock);
    return value;
}

- (size_t)frameStride
{
    pthread_mutex_lock(&_frameLock);
    const size_t value = _frameStride;
    pthread_mutex_unlock(&_frameLock);
    return value;
}

enum {
    RDPMacRemoteShift = 1 << 0,
    RDPMacRemoteControl = 1 << 1,
    RDPMacRemoteAlt = 1 << 2,
    RDPMacRemoteWin = 1 << 3,
};

- (void)syncModifiersLocked:(NSEventModifierFlags)modifiers input:(rdpInput *)input
{
    if (!input)
        return;

    const BOOL shift = (modifiers & NSEventModifierFlagShift) != 0;
    const BOOL control = (modifiers & NSEventModifierFlagControl) != 0;
    const BOOL option = (modifiers & NSEventModifierFlagOption) != 0;
    const BOOL command = (modifiers & NSEventModifierFlagCommand) != 0;
    const BOOL capsLock = (modifiers & NSEventModifierFlagCapsLock) != 0;

    const BOOL wantControl = control || (_commandAsControl && command);
    const BOOL wantWin = command && !_commandAsControl;

    struct {
        uint32_t bit;
        BOOL want;
        uint32_t scancode;
    } states[] = {
        {RDPMacRemoteShift, shift, RDP_SCANCODE_LSHIFT},
        {RDPMacRemoteControl, wantControl, RDP_SCANCODE_LCONTROL},
        {RDPMacRemoteAlt, option, RDP_SCANCODE_LMENU},
        {RDPMacRemoteWin, wantWin, RDP_SCANCODE_LWIN},
    };

    for (size_t i = 0; i < sizeof(states) / sizeof(states[0]); i++) {
        const BOOL have = (_sentModifiers & states[i].bit) != 0;
        if (have == states[i].want)
            continue;
        RDPMacSendScancode(input, states[i].scancode, states[i].want);
        if (states[i].want)
            _sentModifiers |= states[i].bit;
        else
            _sentModifiers &= ~states[i].bit;
    }

    if (capsLock != _capsLockState) {
        RDPMacSendScancode(input, RDP_SCANCODE_CAPSLOCK, TRUE);
        RDPMacSendScancode(input, RDP_SCANCODE_CAPSLOCK, FALSE);
        _capsLockState = capsLock;
    }
}

- (void)sendScancodeForKeyCode:(unsigned short)keyCode down:(BOOL)down input:(rdpInput *)input
{
    uint8_t code = 0;
    uint16_t flags = 0;
    if (!RDPMacScancodeForKeyCode(keyCode, &code, &flags))
        return;

    const uint16_t eventFlags = (down ? KBD_FLAGS_DOWN : KBD_FLAGS_RELEASE) | flags;
    freerdp_input_send_keyboard_event(input, eventFlags, code);
}

- (BOOL)shouldSendUnicodeForCharacters:(NSString *)characters
                             modifiers:(NSEventModifierFlags)modifiers
{
    if (characters.length == 0)
        return NO;
    if ((modifiers & NSEventModifierFlagCommand) != 0)
        return NO;
    if ((modifiers & NSEventModifierFlagControl) != 0)
        return NO;

    BOOL hasNonAscii = NO;
    for (NSUInteger i = 0; i < characters.length; i++) {
        const unichar c = [characters characterAtIndex:i];
        if (c >= 0xF700 && c <= 0xF8FF)
            return NO; // function keys / navigation
        if (c < 0x20)
            return NO; // control characters use scancodes
        if (c >= 0x80)
            hasNonAscii = YES;
    }
    return hasNonAscii;
}

static int RDPMacClampCoordinate(int value, size_t limit)
{
    if (value < 0 || limit == 0)
        return 0;
    if ((size_t)value >= limit)
        return (int)(limit - 1);
    return value;
}

- (void)sendKeyEventWithKeyCode:(unsigned short)keyCode
                     characters:(NSString *)characters
                      modifiers:(NSUInteger)modifiers
                           down:(BOOL)down
                         repeat:(BOOL)isRepeat
{
    (void)isRepeat;
    pthread_mutex_lock(&_apiLock);
    rdpContext *context = _context ? &_context->common.context : NULL;
    rdpInput *input = context ? context->input : NULL;
    if (_state != RDPMacConnectionStateConnected || !input) {
        pthread_mutex_unlock(&_apiLock);
        return;
    }

    [self syncModifiersLocked:(NSEventModifierFlags)modifiers input:input];

    if (down) {
        if ([self shouldSendUnicodeForCharacters:characters
                                       modifiers:(NSEventModifierFlags)modifiers]) {
            for (NSUInteger i = 0; i < characters.length; i++)
                RDPMacSendUnicodeUnit(input, [characters characterAtIndex:i]);
            [_unicodeKeys addObject:@(keyCode)];
        } else {
            [self sendScancodeForKeyCode:keyCode down:YES input:input];
        }
    } else {
        NSNumber *key = @(keyCode);
        if ([_unicodeKeys containsObject:key])
            [_unicodeKeys removeObject:key];
        else
            [self sendScancodeForKeyCode:keyCode down:NO input:input];
    }

    pthread_mutex_unlock(&_apiLock);
}

- (void)sendModifierFlags:(NSUInteger)modifiers
{
    pthread_mutex_lock(&_apiLock);
    rdpContext *context = _context ? &_context->common.context : NULL;
    rdpInput *input = context ? context->input : NULL;
    if (_state == RDPMacConnectionStateConnected && input)
        [self syncModifiersLocked:(NSEventModifierFlags)modifiers input:input];
    pthread_mutex_unlock(&_apiLock);
}

- (void)sendMouseMoveToX:(int)x y:(int)y
{
    pthread_mutex_lock(&_apiLock);
    rdpContext *context = _context ? &_context->common.context : NULL;
    rdpInput *input = context ? context->input : NULL;
    if (_state == RDPMacConnectionStateConnected && input) {
        freerdp_input_send_mouse_event(input, PTR_FLAGS_MOVE,
                                       (UINT16)RDPMacClampCoordinate(x, _frameWidth),
                                       (UINT16)RDPMacClampCoordinate(y, _frameHeight));
    }
    pthread_mutex_unlock(&_apiLock);
}

- (void)sendMouseButton:(int)button down:(BOOL)down x:(int)x y:(int)y
{
    pthread_mutex_lock(&_apiLock);
    rdpContext *context = _context ? &_context->common.context : NULL;
    rdpInput *input = context ? context->input : NULL;
    if (_state == RDPMacConnectionStateConnected && input) {
        const UINT16 px = (UINT16)RDPMacClampCoordinate(x, _frameWidth);
        const UINT16 py = (UINT16)RDPMacClampCoordinate(y, _frameHeight);

        if (button >= 3) {
            UINT16 flags = (button == 3) ? PTR_XFLAGS_BUTTON1 : PTR_XFLAGS_BUTTON2;
            if (down)
                flags |= PTR_XFLAGS_DOWN;
            freerdp_input_send_extended_mouse_event(input, flags, px, py);
        } else {
            UINT16 buttonFlag = PTR_FLAGS_BUTTON1;
            if (button == 1)
                buttonFlag = PTR_FLAGS_BUTTON2;
            else if (button == 2)
                buttonFlag = PTR_FLAGS_BUTTON3;
            UINT16 flags = PTR_FLAGS_MOVE | buttonFlag;
            if (down)
                flags |= PTR_FLAGS_DOWN;
            freerdp_input_send_mouse_event(input, flags, px, py);
        }
    }
    pthread_mutex_unlock(&_apiLock);
}

- (void)sendMouseWheelHorizontal:(BOOL)horizontal points:(double)points x:(int)x y:(int)y
{
    if (points == 0.0)
        return;

    pthread_mutex_lock(&_apiLock);
    rdpContext *context = _context ? &_context->common.context : NULL;
    rdpInput *input = context ? context->input : NULL;
    if (_state != RDPMacConnectionStateConnected || !input) {
        pthread_mutex_unlock(&_apiLock);
        return;
    }

    double *accumulator = horizontal ? &_wheelAccumulatorX : &_wheelAccumulatorY;
    *accumulator += points;
    int steps = (int)*accumulator;
    *accumulator -= steps;
    if (steps > 10)
        steps = 10;
    if (steps < -10)
        steps = -10;

    const UINT16 px = (UINT16)RDPMacClampCoordinate(x, _frameWidth);
    const UINT16 py = (UINT16)RDPMacClampCoordinate(y, _frameHeight);
    const int direction = steps > 0 ? 1 : -1;
    for (int i = 0; i < abs(steps); i++) {
        UINT16 flags = horizontal ? PTR_FLAGS_HWHEEL : PTR_FLAGS_WHEEL;
        if (direction > 0)
            flags |= 120;
        else
            flags |= PTR_FLAGS_WHEEL_NEGATIVE | (0x100 - 120);
        freerdp_input_send_mouse_event(input, flags, px, py);
    }
    pthread_mutex_unlock(&_apiLock);
}

- (void)sendCtrlAltDelete
{
    pthread_mutex_lock(&_apiLock);
    rdpContext *context = _context ? &_context->common.context : NULL;
    rdpInput *input = context ? context->input : NULL;
    if (_state != RDPMacConnectionStateConnected || !input) {
        pthread_mutex_unlock(&_apiLock);
        return;
    }
    RDPMacSendScancode(input, RDP_SCANCODE_LCONTROL, TRUE);
    RDPMacSendScancode(input, RDP_SCANCODE_LMENU, TRUE);
    RDPMacSendScancode(input, RDP_SCANCODE_END, TRUE);
    RDPMacSendScancode(input, RDP_SCANCODE_END, FALSE);
    RDPMacSendScancode(input, RDP_SCANCODE_LMENU, FALSE);
    RDPMacSendScancode(input, RDP_SCANCODE_LCONTROL, FALSE);
    _sentModifiers = 0;
    pthread_mutex_unlock(&_apiLock);
    [self logMessage:@"Отправлена комбинация Ctrl+Alt+Delete (Ctrl+Alt+End)" level:0];
}

- (BOOL)requestDesktopSize:(NSUInteger)width height:(NSUInteger)height
{
    NSUInteger safeWidth = MAX((NSUInteger)200, MIN(width, RDPMacMaxFrameDimension));
    NSUInteger safeHeight = MAX((NSUInteger)200, MIN(height, RDPMacMaxFrameDimension));
    safeWidth &= ~(NSUInteger)1;
    safeHeight &= ~(NSUInteger)1;

    pthread_mutex_lock(&_apiLock);
    if (_state != RDPMacConnectionStateConnected || !_context || !_context->disp ||
        !_context->disp->SendMonitorLayout) {
        pthread_mutex_unlock(&_apiLock);
        [self logMessage:@"DisplayControl недоступен: изменение размера не отправлено" level:1];
        return NO;
    }

    DISPLAY_CONTROL_MONITOR_LAYOUT layout = {0};
    layout.Flags = DISPLAY_CONTROL_MONITOR_PRIMARY;
    layout.Width = (UINT32)safeWidth;
    layout.Height = (UINT32)safeHeight;
    layout.PhysicalWidth = (UINT32)safeWidth;
    layout.PhysicalHeight = (UINT32)safeHeight;
    layout.Orientation = 0;
    layout.DesktopScaleFactor = 100;
    layout.DeviceScaleFactor = 100;

    const UINT rc = _context->disp->SendMonitorLayout(_context->disp, 1, &layout);
    pthread_mutex_unlock(&_apiLock);
    if (rc != CHANNEL_RC_OK) {
        [self logMessage:[NSString stringWithFormat:@"DisplayControl: запрос размера не принят "
                                                    @"(0x%08X)",
                                                    rc]
                    level:1];
        return NO;
    }
    [self logMessage:[NSString stringWithFormat:@"DisplayControl: запрошен размер %lux%lu",
                                                (unsigned long)safeWidth,
                                                (unsigned long)safeHeight]
                level:0];
    return YES;
}

- (void)clipboardThreadMonitorReady
{
    [_clipboard handleMonitorReady];
}

- (void)clipboardThreadCapabilities:(uint32_t)generalFlags version:(uint32_t)version
{
    [_clipboard handleServerCapabilitiesGeneralFlags:generalFlags version:version];
}

- (void)clipboardThreadFormatList:(NSArray<NSNumber *> *)formatIds
                            names:(NSArray<NSString *> *)formatNames
{
    [_clipboard handleServerFormatListIds:formatIds names:formatNames];
}

- (void)clipboardThreadFormatListResponse:(uint16_t)flags
{
    [_clipboard handleServerFormatListResponseFlags:flags];
}

- (void)clipboardThreadFormatDataRequest:(uint32_t)formatId
{
    [_clipboard handleServerFormatDataRequestFormat:formatId];
}

- (void)clipboardThreadFormatDataResponse:(NSData *)data flags:(uint16_t)flags
{
    [_clipboard handleServerFormatDataResponse:data flags:flags];
}

- (void)clipboardThreadDisconnected
{
    [_clipboard handleChannelDisconnected];
}

- (void)notifyClipboardDiagnostics
{
    id<RDPMacClientDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(rdpClient:didUpdateClipboardDiagnostics:)]) {
        [delegate rdpClient:self didUpdateClipboardDiagnostics:[self clipboardDiagnostics]];
    }
}

- (RDPMacClipboardDiagnostics *)clipboardDiagnostics
{
    return [_clipboard diagnostics];
}

- (void)clipboardSendLocal
{
    [_clipboard sendLocalClipboard];
}

- (void)clipboardRequestRemote
{
    [_clipboard requestRemoteClipboard];
}

- (void)clipboardResync
{
    [_clipboard resync];
}

@end
