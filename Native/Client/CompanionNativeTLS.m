#import "CompanionNativeTLS.h"
#include <openssl/ssl.h>
#include <openssl/x509v3.h>
#include <openssl/rand.h>
#include <openssl/err.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>

static BOOL nativeFailure(NSError **error, NSInteger code) {
    if (error) *error = [NSError errorWithDomain:@"CompanionNativeTLS" code:code userInfo:nil];
    return NO;
}
static NSData *certificateBytes(X509 *cert) {
    int length = i2d_X509(cert, NULL);
    if (length < 1 || length > 4096) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)length];
    unsigned char *cursor = data.mutableBytes;
    return i2d_X509(cert, &cursor) == length ? data : nil;
}
static X509 *parseCertificate(NSData *der, BOOL server) {
    if (der.length < 1 || der.length > 4096) return NULL;
    const unsigned char *cursor = der.bytes;
    X509 *cert = d2i_X509(NULL, &cursor, (long)der.length);
    EVP_PKEY *key = cert ? X509_get_pubkey(cert) : NULL;
    BOOL valid = cert && cursor == (const unsigned char *)der.bytes + der.length
        && [certificateBytes(cert) isEqualToData:der] && key
        && EVP_PKEY_base_id(key) == EVP_PKEY_RSA && EVP_PKEY_bits(key) >= 2048
        && X509_NAME_cmp(X509_get_subject_name(cert), X509_get_issuer_name(cert)) == 0
        && X509_verify(cert, key) == 1
        && X509_cmp_current_time(X509_get0_notBefore(cert)) < 0
        && X509_cmp_current_time(X509_get0_notAfter(cert)) > 0
        && X509_check_purpose(cert, server ? X509_PURPOSE_SSL_SERVER : X509_PURPOSE_SSL_CLIENT, 0) == 1;
    // Require an explicit matching EKU, not an unconstrained certificate.
    EXTENDED_KEY_USAGE *usage = cert ? X509_get_ext_d2i(cert, NID_ext_key_usage, NULL, NULL) : NULL;
    BOOL purpose = NO;
    for (int i = 0; usage && i < sk_ASN1_OBJECT_num(usage); i++) {
        if (OBJ_obj2nid(sk_ASN1_OBJECT_value(usage, i)) == (server ? NID_server_auth : NID_client_auth)) purpose = YES;
    }
    EXTENDED_KEY_USAGE_free(usage);
    EVP_PKEY_free(key);
    if (!valid || !purpose) { X509_free(cert); return NULL; }
    return cert;
}
static int pinnedPeer(int verified, X509_STORE_CTX *store) {
    (void)verified;
    SSL *ssl = X509_STORE_CTX_get_ex_data(store, SSL_get_ex_data_X509_STORE_CTX_idx());
    X509 *pin = SSL_CTX_get_app_data(SSL_get_SSL_CTX(ssl));
    if (pin && X509_STORE_CTX_get_error_depth(store) == 0
        && [certificateBytes(X509_STORE_CTX_get_current_cert(store)) isEqualToData:certificateBytes(pin)]
        && X509_cmp_current_time(X509_get0_notBefore(pin)) < 0
        && X509_cmp_current_time(X509_get0_notAfter(pin)) > 0) {
        X509_STORE_CTX_set_error(store, X509_V_OK);
        return 1;
    }
    return 0;
}
static BOOL waitSocket(int fd, short events, double deadline) {
    while (NSProcessInfo.processInfo.systemUptime < deadline) {
        struct pollfd descriptor = {fd, events, 0};
        int result = poll(&descriptor, 1, 50);
        if (result > 0) return (descriptor.revents & events) != 0;
        if (result < 0 && errno != EINTR) return NO;
    }
    return NO;
}
static BOOL retrySSL(SSL *ssl, int result, int fd, double deadline) {
    int failure = SSL_get_error(ssl, result);
    if (failure == SSL_ERROR_WANT_READ) return waitSocket(fd, POLLIN, deadline);
    if (failure == SSL_ERROR_WANT_WRITE) return waitSocket(fd, POLLOUT, deadline);
    return NO;
}

@implementation CompanionNativeTLS {
    NSLock *_lock;
    EVP_PKEY *_key;
    X509 *_certificate;
    NSData *_certificateDER;
    NSData *_pin;
    NSString *_address;
    uint16_t _port;
    BOOL _retired, _busy;
    int _socket;
}
+ (instancetype)createWithError:(NSError **)error { return [[self alloc] initWithError:error]; }
- (instancetype)initWithError:(NSError **)error {
    if (!(self = [super init])) return nil;
    _lock = [NSLock new]; _socket = -1;
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, NULL);
    BOOL ok = ctx && EVP_PKEY_keygen_init(ctx) > 0 && EVP_PKEY_CTX_set_rsa_keygen_bits(ctx, 2048) > 0
        && EVP_PKEY_keygen(ctx, &_key) > 0;
    EVP_PKEY_CTX_free(ctx);
    _certificate = ok ? X509_new() : NULL;
    unsigned char serial[16] = {0};
    ok = ok && _certificate && RAND_bytes(serial, sizeof(serial)) == 1;
    serial[0] &= 0x7f; serial[0] |= 1;
    BIGNUM *number = ok ? BN_bin2bn(serial, sizeof(serial), NULL) : NULL;
    ASN1_INTEGER *integer = number ? BN_to_ASN1_INTEGER(number, NULL) : NULL;
    ok = ok && integer && X509_set_version(_certificate, 2) == 1
        && X509_set_serialNumber(_certificate, integer) == 1
        && X509_gmtime_adj(X509_getm_notBefore(_certificate), -60) != NULL
        && X509_gmtime_adj(X509_getm_notAfter(_certificate), 86400) != NULL
        && X509_set_pubkey(_certificate, _key) == 1;
    BN_clear_free(number); ASN1_INTEGER_free(integer); OPENSSL_cleanse(serial, sizeof(serial));
    if (ok) {
        X509_NAME *name = X509_get_subject_name(_certificate);
        ok = X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
            (const unsigned char *)"MacCompanion Ephemeral Native Client", -1, -1, 0) == 1
            && X509_set_issuer_name(_certificate, name) == 1;
        for (NSString *value in @[@"critical,CA:FALSE", @"critical,digitalSignature,keyEncipherment", @"clientAuth"]) {
            int nid = [value containsString:@"CA:"] ? NID_basic_constraints : [value containsString:@"digitalSignature"] ? NID_key_usage : NID_ext_key_usage;
            X509_EXTENSION *ext = X509V3_EXT_conf_nid(NULL, NULL, nid, (char *)value.UTF8String);
            ok = ok && ext && X509_add_ext(_certificate, ext, -1) == 1;
            X509_EXTENSION_free(ext);
        }
        ok = ok && X509_sign(_certificate, _key, EVP_sha256()) > 0;
    }
    _certificateDER = ok ? certificateBytes(_certificate) : nil;
    if (!_certificateDER || ![CompanionNativeTLS validateCertificateDER:_certificateDER server:NO]) {
        [self retire]; nativeFailure(error, 1); return nil;
    }
    return self;
}
- (void)dealloc { [self retire]; }
- (NSData *)certificateDER { [_lock lock]; NSData *der = _retired ? nil : [_certificateDER copy]; [_lock unlock]; return der; }
+ (BOOL)validateCertificateDER:(NSData *)der server:(BOOL)server {
    X509 *cert = parseCertificate(der, server); BOOL valid = cert != NULL; X509_free(cert); return valid;
}
- (BOOL)bindAddress:(NSString *)address portBase:(uint16_t)portBase hostCertificateDER:(NSData *)der error:(NSError **)error {
    struct in_addr ipv4; struct in6_addr ipv6;
    if (address.length > 64 || !(inet_pton(AF_INET, address.UTF8String, &ipv4) == 1 || inet_pton(AF_INET6, address.UTF8String, &ipv6) == 1)
        || portBase < 1030 || portBase >= 65500 || ![CompanionNativeTLS validateCertificateDER:der server:YES]) return nativeFailure(error, 2);
    [_lock lock];
    BOOL ok = !_retired && !_address && !_busy;
    if (ok) { _address = [address copy]; _pin = [der copy]; _port = portBase - 5; }
    [_lock unlock]; return ok ? YES : nativeFailure(error, 2);
}
- (NSData *)requestPath:(NSString *)path error:(NSError **)error {
    // This seam accepts only the four managed native operations, never a URL.
    NSString *operation = [[path componentsSeparatedByString:@"?"] firstObject];
    NSArray *operations = @[@"/serverinfo", @"/applist", @"/launch", @"/cancel"];
    BOOL denialProbe = NO;
#if MACCOMPANION_MANAGED_ROUTE_PROBE
    // Only the disposable host-probe target defines this flag. SDK frameworks
    // retain the closed four-operation interface and HTTP 200 requirement.
    denialProbe = [@[@"/pair", @"/resume", @"/appasset"] containsObject:operation];
    if (denialProbe) operations = [operations arrayByAddingObject:operation];
#endif
    NSString *expectedStatus = denialProbe ? @"404 " : @"200 ";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/-?=&_.%:"];
    if ([path rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound
        || path.length > 4096 || ![operations containsObject:operation]
        || [path rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound
        || ![path canBeConvertedToEncoding:NSASCIIStringEncoding] || [path containsString:@"#"]) {
        nativeFailure(error, 3); return nil;
    }
    [_lock lock];
    if (_retired || _busy || !_address) { [_lock unlock]; nativeFailure(error, 4); return nil; }
    _busy = YES;
    NSString *address = _address; NSData *pinDER = _pin; uint16_t port = _port;
    EVP_PKEY *key = _key; X509 *cert = _certificate; EVP_PKEY_up_ref(key); X509_up_ref(cert);
    [_lock unlock];
    X509 *pin = parseCertificate(pinDER, YES);
    SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
    SSL *ssl = NULL; int fd = -1; NSData *body = nil;
    NSMutableData *response = [NSMutableData new];
    double deadline = NSProcessInfo.processInfo.systemUptime + 5;
    NSString *host = nil, *headers = nil, *lengthText = nil;
    NSData *request = nil, *separator = nil;
    NSArray<NSString *> *lines = nil;
    BOOL ended = NO;
    if (!pin || !ctx || SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION) != 1
        || SSL_CTX_use_certificate(ctx, cert) != 1 || SSL_CTX_use_PrivateKey(ctx, key) != 1) goto cleanup;
    SSL_CTX_set_app_data(ctx, pin);
    SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, pinnedPeer);
    struct sockaddr_storage storage = {0}; socklen_t size;
    struct sockaddr_in *v4 = (struct sockaddr_in *)&storage;
    if (inet_pton(AF_INET, address.UTF8String, &v4->sin_addr) == 1) {
        v4->sin_family = AF_INET; v4->sin_port = htons(port); size = sizeof(*v4);
    } else {
        struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)&storage;
        if (inet_pton(AF_INET6, address.UTF8String, &v6->sin6_addr) != 1) goto cleanup;
        v6->sin6_family = AF_INET6; v6->sin6_port = htons(port); size = sizeof(*v6);
    }
    fd = socket(storage.ss_family, SOCK_STREAM, 0);
    if (fd < 0 || fcntl(fd, F_SETFL, O_NONBLOCK) != 0) goto cleanup;
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    [_lock lock]; BOOL retired = _retired; if (!retired) _socket = fd; [_lock unlock];
    if (retired) goto cleanup;
    if (connect(fd, (struct sockaddr *)&storage, size) != 0) {
        if (errno != EINPROGRESS || !waitSocket(fd, POLLOUT, deadline)) goto cleanup;
        int status = 0; socklen_t statusLength = sizeof(status);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &status, &statusLength) != 0 || status != 0) goto cleanup;
    }
    ssl = SSL_new(ctx);
    if (!ssl || SSL_set_fd(ssl, fd) != 1) goto cleanup;
    int result;
    while ((result = SSL_connect(ssl)) != 1) { if (!retrySSL(ssl, result, fd, deadline)) goto cleanup; }
    X509 *peer = SSL_get1_peer_certificate(ssl);
    BOOL matched = peer && [certificateBytes(peer) isEqualToData:pinDER] && SSL_get_verify_result(ssl) == X509_V_OK;
    X509_free(peer); if (!matched) goto cleanup;
    host = [address containsString:@":"] ? [NSString stringWithFormat:@"[%@]", address] : address;
    request = [[NSString stringWithFormat:@"GET %@ HTTP/1.1\r\nHost: %@:%u\r\nConnection: close\r\n\r\n", path, host, port] dataUsingEncoding:NSASCIIStringEncoding];
    for (NSUInteger written = 0; written < request.length;) {
        result = SSL_write(ssl, (const char *)request.bytes + written, (int)(request.length - written));
        if (result > 0) written += (NSUInteger)result;
        else if (!retrySSL(ssl, result, fd, deadline)) goto cleanup;
    }
    while (NSProcessInfo.processInfo.systemUptime < deadline) {
        unsigned char buffer[8192]; result = SSL_read(ssl, buffer, sizeof(buffer));
        if (result > 0) {
            if (response.length + (NSUInteger)result > 1024 * 1024) goto cleanup;
            [response appendBytes:buffer length:(NSUInteger)result];
        } else {
            int failure = SSL_get_error(ssl, result);
            if (failure == SSL_ERROR_ZERO_RETURN) { ended = YES; break; }
            // Sunshine closes HTTP responses without a TLS close_notify.
            if (failure == SSL_ERROR_SSL && ERR_GET_REASON(ERR_peek_last_error()) == SSL_R_UNEXPECTED_EOF_WHILE_READING) { ended = YES; break; }
            if (!retrySSL(ssl, result, fd, deadline)) goto cleanup;
        }
    }
    if (!ended) goto cleanup;
    separator = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange boundary = [response rangeOfData:separator options:0 range:NSMakeRange(0, response.length)];
    if (boundary.location == NSNotFound || boundary.location > 16384) goto cleanup;
    headers = [[NSString alloc] initWithData:[response subdataWithRange:NSMakeRange(0, boundary.location)] encoding:NSASCIIStringEncoding];
    lines = [headers componentsSeparatedByString:@"\r\n"];
    if (![lines.firstObject hasPrefix:[@"HTTP/1.1 " stringByAppendingString:expectedStatus]]
        && ![lines.firstObject hasPrefix:[@"HTTP/1.0 " stringByAppendingString:expectedStatus]]) goto cleanup;
    lengthText = nil;
    for (NSString *line in lines) {
        if ([[line lowercaseString] hasPrefix:@"transfer-encoding:"]) goto cleanup;
        if ([[line lowercaseString] hasPrefix:@"content-length:"]) {
            if (lengthText) goto cleanup;
            lengthText = [[line substringFromIndex:15] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }
    }
    if (!lengthText.length || [lengthText rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) goto cleanup;
    NSUInteger start = boundary.location + boundary.length;
    if (lengthText.longLongValue < 1 || (unsigned long long)lengthText.longLongValue != response.length - start) goto cleanup;
    body = [response subdataWithRange:NSMakeRange(start, response.length - start)];
cleanup:
    [_lock lock];
    if (_socket == fd) _socket = -1;
    if (_retired) body = nil;
    _busy = NO;
    [_lock unlock];
    SSL_free(ssl); SSL_CTX_free(ctx); X509_free(pin); X509_free(cert); EVP_PKEY_free(key);
    if (fd >= 0) close(fd);
    if (!body) nativeFailure(error, 5);
    return body;
}
- (void)retire {
    [_lock lock];
    _retired = YES;
    if (_socket >= 0) shutdown(_socket, SHUT_RDWR);
    EVP_PKEY_free(_key); _key = NULL; X509_free(_certificate); _certificate = NULL;
    _certificateDER = nil; _pin = nil; _address = nil;
    [_lock unlock];
}
@end
