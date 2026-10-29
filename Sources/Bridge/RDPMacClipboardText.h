//
//  RDPMacClipboardText.h
//  Text <-> CLIPRDR payload conversion. Foundation only, no FreeRDP types,
//  so it can be unit tested without a live session.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// CF_UNICODETEXT (Windows clipboard format id).
extern const uint32_t RDPMacClipboardFormatUnicodeText;
/// CF_TEXT (ANSI, best effort).
extern const uint32_t RDPMacClipboardFormatText;

/// Human readable name used in diagnostics (no content).
NSString *RDPMacClipboardFormatName(uint32_t formatId);

/// Serializes text for CB_FORMAT_DATA_RESPONSE.
/// CF_UNICODETEXT: UTF-16LE with a trailing NUL, as required by [MS-RDPECLIP].
/// CF_TEXT: CP1251 when possible, otherwise CP1252 for ASCII/Latin text.
/// Returns nil and fills error for unsupported characters/format.
NSData *_Nullable RDPMacClipboardEncodeText(NSString *text, uint32_t formatId,
                                           NSError *_Nullable *_Nullable error);

/// Deserializes CF_UNICODETEXT (UTF-16LE, optional trailing NUL) or CF_TEXT.
NSString *_Nullable RDPMacClipboardDecodeText(NSData *data, uint32_t formatId);

/// YES when the string can be represented in the given format.
BOOL RDPMacClipboardCanEncodeText(NSString *text, uint32_t formatId);

NS_ASSUME_NONNULL_END
