// Include the exact source copy used by the embedded framework. Exercise its
// prefix stripping and IDR slow path without sockets, capture or decoding.
#include "VideoDepacketizer.c"
#include <stdio.h>
#include <stdlib.h>
#define Require(x) do { if (!(x)) { fprintf(stderr,"Native depacketizer check failed at line %d\n",__LINE__); abort(); } } while (0)
int NegotiatedVideoFormat;
static void clearChain(void) {
    PLENTRY item = nalChainHead;
    while (item) { PLENTRY next = item->next; free(((PLENTRY_INTERNAL)item)->allocPtr); item = next; }
    nalChainHead = nalChainTail = NULL; nalChainDataLength = 0;
}
static size_t nal(uint8_t *bytes, bool hevc, int type) {
    bytes[0] = bytes[1] = bytes[2] = 0; bytes[3] = 1;
    bytes[4] = hevc ? (uint8_t)(type << 1) : (uint8_t)type;
    bytes[5] = hevc ? 1 : 0xb8; bytes[6] = 0xb8;
    return hevc ? 7 : 6;
}
static void verify(const CompanionNativeSurfaceEpoch *epoch, bool hevc, bool idr, unsigned markers) {
    uint8_t bytes[512]; size_t length = 0;
    length += nal(bytes + length,hevc,hevc ? 35 : 9); // AUD
    if (markers) {
        size_t size = CompanionNativeEpochSEI(epoch,hevc,bytes + length,sizeof(bytes) - length);
        // An unrelated SEI is still stripped, without suppressing our marker.
        bytes[length + (hevc ? 8 : 7)] ^= 1; length += size;
    }
    for (unsigned i = 0; i < markers; i++) length += CompanionNativeEpochSEI(epoch,hevc,bytes + length,sizeof(bytes) - length);
    if (idr) {
        if (hevc) length += nal(bytes + length,true,32);
        length += nal(bytes + length,hevc,hevc ? 33 : 7);
        length += nal(bytes + length,hevc,hevc ? 34 : 8);
    }
    length += nal(bytes + length,hevc,hevc ? (idr ? 19 : 1) : (idr ? 5 : 1));
    NegotiatedVideoFormat = hevc ? VIDEO_FORMAT_H265 : VIDEO_FORMAT_H264;
    BUFFER_DESC buffer = {(char *)bytes,0,(int)length};
    // Match the ordinary first-packet stripping site in processRtpPayload().
    if (isAccessUnitDelimiter(&buffer)) skipToNextNal(&buffer);
    while (isSeiNal(&buffer)) companionSkipPrefix(&buffer);
    if (idr) {
        Require(isIdrFrameStart(&buffer));
        processAvcHevcRtpPayloadSlow(&buffer,NULL);
        Require(frameType == FRAME_TYPE_IDR);
        PLENTRY item = nalChainHead;
        if (hevc) { Require(item->bufferType == BUFFER_TYPE_VPS); item = item->next; }
        Require(item->bufferType == BUFFER_TYPE_SPS); item = item->next;
        Require(item->bufferType == BUFFER_TYPE_PPS);
    } else queueFragment(NULL,buffer.data,buffer.offset,buffer.length);
    uint8_t picture[512]; size_t size = 0;
    for (PLENTRY item = nalChainHead; item; item = item->next) {
        if (item->bufferType == BUFFER_TYPE_PICDATA) { memcpy(picture + size,item->data,(size_t)item->length); size += (size_t)item->length; }
    }
    CompanionNativeSurfaceEpoch actual; bool independent = false;
    int result = CompanionNativeEpochInspect(picture,size,hevc,&actual,&independent);
    Require(result == (markers > 1 ? -1 : markers ? 1 : 0));
    if (markers == 1) { Require(CompanionNativeEpochEqual(&actual,epoch)); Require(independent == idr); }
    clearChain();
    // Also exercise the slow path's own prefix loop before parameter sets.
    if (idr) {
        buffer = (BUFFER_DESC){(char *)bytes,0,(int)length};
        processAvcHevcRtpPayloadSlow(&buffer,NULL);
        size = 0;
        for (PLENTRY item = nalChainHead; item; item = item->next) if (item->bufferType == BUFFER_TYPE_PICDATA) {
            memcpy(picture + size,item->data,(size_t)item->length); size += (size_t)item->length;
        }
        Require(CompanionNativeEpochInspect(picture,size,hevc,&actual,&independent) == (markers > 1 ? -1 : markers ? 1 : 0));
        clearChain();
    }
}
int main(int argc, const char **argv) {
    Require(argc == 2 && strlen(argv[1]) == 96);
    uint8_t bytes[48];
    for (size_t i = 0; i < 48; i++) { unsigned value; Require(sscanf(argv[1]+2*i,"%2x",&value) == 1); bytes[i] = (uint8_t)value; }
    CompanionNativeSurfaceEpoch epoch; Require(CompanionNativeEpochDecode(bytes,48,&epoch));
    for (int hevc = 0; hevc < 2; hevc++) for (int idr = 0; idr < 2; idr++) for (unsigned markers = 0; markers < 3; markers++) verify(&epoch,hevc,idr,markers);
    puts("Native depacketizer: actual pinned ordinary/IDR paths preserve H.264/HEVC epoch, strip unrelated prefixes, preserve duplicate rejection; no content retained.");
    return 0;
}
