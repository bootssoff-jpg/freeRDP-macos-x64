//
//  crypto_tests.m
//  Verifies that every hash/cipher primitive used while establishing an RDP
//  session is actually usable, against published test vectors.
//
//  Regression guard: OpenSSL 3 no longer ships MD4 (or RC4) in the default
//  provider. NTLM, and therefore CredSSP/NLA, needs MD4 for the NT hash. When
//  MD4 cannot be initialised, the connection dies later with the generic
//  FREERDP_ERROR_CONNECT_TRANSPORT_FAILED (0x0002000D), which hides the real
//  cause. These tests fail loudly in that situation instead.
//
//  The test process intentionally drops OpenSSL environment overrides so that
//  it exercises the same code path as a Finder-launched .app.
//

#import <Foundation/Foundation.h>
#include <winpr/crypto.h>
#include <winpr/ntlm.h>

#include <openssl/evp.h>
#include <openssl/provider.h>
#include <openssl/err.h>

#include <string.h>

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

static NSString *hexString(const unsigned char *data, size_t length)
{
    NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
    for (size_t i = 0; i < length; i++)
        [hex appendFormat:@"%02x", data[i]];
    return hex;
}

static void expectDigest(WINPR_MD_TYPE md, const char *input, size_t inputLength,
                         NSString *expectedHex, NSString *label)
{
    unsigned char output[WINPR_SHA512_DIGEST_LENGTH] = {0};
    const BOOL ok = winpr_Digest(md, input, inputLength, output, sizeof(output));
    NSString *actual = ok ? hexString(output, expectedHex.length / 2) : @"(init failed)";
    expect(ok && [actual isEqualToString:expectedHex],
           [NSString stringWithFormat:@"%@ = %@ (got %@)", label, expectedHex, actual]);
}

static void expectOpenSSLDigest(const char *name)
{
    EVP_MD *md = EVP_MD_fetch(NULL, name, NULL);
    BOOL ok = md != NULL;
    EVP_MD_CTX *ctx = ok ? EVP_MD_CTX_new() : NULL;
    if (!ctx || EVP_DigestInit_ex(ctx, md, NULL) != 1)
        ok = NO;
    ERR_clear_error();
    EVP_MD_CTX_free(ctx);
    EVP_MD_free(md);
    expect(ok, [NSString stringWithFormat:@"OpenSSL digest %s is usable", name]);
}

static void expectOpenSSLCipher(const char *name)
{
    EVP_CIPHER *cipher = EVP_CIPHER_fetch(NULL, name, NULL);
    BOOL ok = cipher != NULL;
    EVP_CIPHER_CTX *ctx = ok ? EVP_CIPHER_CTX_new() : NULL;
    unsigned char key[32] = {0};
    unsigned char iv[16] = {0};
    if (!ctx || EVP_EncryptInit_ex(ctx, cipher, NULL, key, iv) != 1)
        ok = NO;
    ERR_clear_error();
    EVP_CIPHER_CTX_free(ctx);
    EVP_CIPHER_free(cipher);
    expect(ok, [NSString stringWithFormat:@"OpenSSL cipher %s is usable", name]);
}

static void expectRC4(void)
{
    // Classic RC4 vector: key "Key", plaintext "Plaintext".
    static const unsigned char expected[9] = {0xbb, 0xf3, 0x16, 0xe8, 0xd9,
                                              0x40, 0xaf, 0x0a, 0xd3};
    const char *plaintext = "Plaintext";
    unsigned char output[9] = {0};
    WINPR_RC4_CTX *rc4 = winpr_RC4_New("Key", 3);
    BOOL ok = rc4 != NULL && winpr_RC4_Update(rc4, 9, plaintext, output);
    winpr_RC4_Free(rc4);
    expect(ok && memcmp(output, expected, sizeof(expected)) == 0,
           @"RC4 (legacy RDP security mode) produces the published vector");
}

int main(void)
{
    @autoreleasepool {
        // A Finder-launched app inherits no OpenSSL configuration. Simulate it.
        unsetenv("OPENSSL_MODULES");
        unsetenv("OPENSSL_CONF");
        unsetenv("OPENSSL_CONF_INCLUDE");
        unsetenv("OPENSSL_ENGINES");
        (void)OSSL_PROVIDER_load(NULL, "default");

        printf("OpenSSL: %s\n", OpenSSL_version(OPENSSL_VERSION));

        // RFC 1320 (MD4) vectors. NTLM hashes the UTF-16LE password with MD4.
        expectDigest(WINPR_MD_MD4, "", 0, @"31d6cfe0d16ae931b73c59d7e0c089c0", @"MD4(\"\")");
        expectDigest(WINPR_MD_MD4, "abc", 3, @"a448017aaf21d8525fc10ae87aa6729d",
                     @"MD4(\"abc\")");
        expectDigest(WINPR_MD_MD4, "message digest", 14,
                     @"d9130a8164549fe818874806e1c7014b", @"MD4(\"message digest\")");
        expectDigest(WINPR_MD_MD4, "abcdefghijklmnopqrstuvwxyz", 26,
                     @"d79e1c308aa5bbcdeea8ed63df412da9", @"MD4(alphabet)");

        // RFC 1321 / FIPS 180-4 vectors for the remaining digests.
        expectDigest(WINPR_MD_MD5, "abc", 3, @"900150983cd24fb0d6963f7d28e17f72",
                     @"MD5(\"abc\")");
        expectDigest(WINPR_MD_SHA1, "abc", 3,
                     @"a9993e364706816aba3e25717850c26c9cd0d89d", @"SHA1(\"abc\")");
        expectDigest(WINPR_MD_SHA256, "abc", 3,
                     @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                     @"SHA256(\"abc\")");

        // MS-NLMP 4.2 test data: user "User", domain "Domain", password "Password".
        unsigned char ntHash[WINPR_MD4_DIGEST_LENGTH] = {0};
        const BOOL ntOk = NTOWFv1A("Password", 8, ntHash);
        expect(ntOk && [hexString(ntHash, sizeof(ntHash))
                           isEqualToString:@"a4f49c406510bdcab6824ee7c30fd852"],
               @"NTLM NT hash (NTOWFv1) matches MS-NLMP");

        unsigned char ntlmV2[WINPR_MD5_DIGEST_LENGTH] = {0};
        const BOOL v2Ok = NTOWFv2A("Password", 8, "User", 4, "Domain", 6, ntlmV2);
        expect(v2Ok && [hexString(ntlmV2, sizeof(ntlmV2))
                           isEqualToString:@"0c868a403bfd7a93a3001ef22ef02e3f"],
               @"NTLMv2 hash (NTOWFv2) matches MS-NLMP");

        // RFC 2202 HMAC-MD5 test case 1 (used by NTLM message signing).
        static const unsigned char hmacKey[16] = {0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b,
                                                  0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b,
                                                  0x0b, 0x0b};
        unsigned char hmac[WINPR_MD5_DIGEST_LENGTH] = {0};
        const BOOL hmacOk = winpr_HMAC(WINPR_MD_MD5, hmacKey, sizeof(hmacKey), "Hi There", 8,
                                       hmac, sizeof(hmac));
        expect(hmacOk && [hexString(hmac, sizeof(hmac))
                             isEqualToString:@"9294727a3638bb1c13f48ef8158bfc9d"],
               @"HMAC-MD5 matches RFC 2202");

        expectRC4();

        // TLS needs the default provider only. These must work without any
        // OPENSSL_MODULES/OPENSSL_CONF environment or build-tree module path.
        expectOpenSSLDigest("SHA256");
        expectOpenSSLDigest("SHA384");
        expectOpenSSLCipher("AES-128-GCM");
        expectOpenSSLCipher("AES-256-GCM");
        expectOpenSSLCipher("DES-EDE3-CBC");

        if (gFailures == 0) {
            printf("RESULT: OK\n");
            return 0;
        }
        printf("RESULT: %d FAILURES\n", gFailures);
        return 1;
    }
}
