#include "PNGShrink.h"
#include "libimagequant/libimagequant.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

static void put32(unsigned char *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }

/// Appends one PNG chunk (length, type, data, CRC) at `*at`.
static void chunk(unsigned char **at, const char *type, const unsigned char *data, uint32_t len) {
    unsigned char *p = *at;
    put32(p, len);
    memcpy(p + 4, type, 4);
    if (len) memcpy(p + 8, data, len);
    put32(p + 8 + len, (uint32_t)crc32(0, p + 4, len + 4));
    *at = p + 12 + len;
}

unsigned char *us_shrink_png(const unsigned char *rgba, int width, int height,
                             int min_quality, int max_quality, double dpi, size_t *out_len) {
    if (!rgba || width <= 0 || height <= 0 || !out_len) return NULL;
    unsigned char *png = NULL, *pixels = NULL, *idat = NULL;
    liq_attr *attr = liq_attr_create();
    liq_image *img = attr ? liq_image_create_rgba(attr, rgba, width, height, 0) : NULL;
    liq_result *res = NULL;
    if (!img || liq_set_quality(attr, min_quality, max_quality) != LIQ_OK || liq_image_quantize(img, attr, &res) != LIQ_OK) goto done;
    liq_set_dithering_level(res, 1.0f);

    // Each row: filter byte 0, then one palette index per pixel.
    size_t w = (size_t)width, h = (size_t)height, raw_len = h * (w + 1);
    pixels = malloc(w * h);
    unsigned char *raw = malloc(raw_len);
    if (!pixels || !raw) { free(raw); goto done; }
    if (liq_write_remapped_image(res, img, pixels, w * h) != LIQ_OK) { free(raw); goto done; }
    for (size_t y = 0; y < h; y++) { raw[y * (w + 1)] = 0; memcpy(raw + y * (w + 1) + 1, pixels + y * w, w); }
    uLongf idat_len = compressBound((uLong)raw_len);
    idat = malloc(idat_len);
    int z = idat ? compress2(idat, &idat_len, raw, (uLong)raw_len, 9) : Z_MEM_ERROR;
    free(raw);
    if (z != Z_OK) goto done;

    const liq_palette *pal = liq_get_palette(res);
    unsigned char plte[768], trns[256];
    uint32_t n = pal->count, trns_len = 0;
    for (uint32_t i = 0; i < n; i++) {
        plte[i * 3] = pal->entries[i].r; plte[i * 3 + 1] = pal->entries[i].g; plte[i * 3 + 2] = pal->entries[i].b;
        trns[i] = pal->entries[i].a;
        if (trns[i] != 255) trns_len = i + 1;   // tRNS may stop at the last see-through colour
    }

    size_t total = 8 + (12 + 13) + (12 + 1) + (12 + 9) + (12 + n * 3) + (12 + trns_len) + (12 + idat_len) + 12;
    png = malloc(total);
    if (!png) goto done;
    unsigned char *p = png;
    memcpy(p, "\x89PNG\r\n\x1a\n", 8); p += 8;
    unsigned char ihdr[13];
    put32(ihdr, (uint32_t)width); put32(ihdr + 4, (uint32_t)height);
    ihdr[8] = 8; ihdr[9] = 3; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;   // 8-bit, palette
    chunk(&p, "IHDR", ihdr, 13);
    unsigned char srgb = 0;   // perceptual
    chunk(&p, "sRGB", &srgb, 1);
    if (dpi > 0) {
        unsigned char phys[9];
        uint32_t ppm = (uint32_t)(dpi / 0.0254 + 0.5);
        put32(phys, ppm); put32(phys + 4, ppm); phys[8] = 1;   // pixels per metre
        chunk(&p, "pHYs", phys, 9);
    }
    chunk(&p, "PLTE", plte, n * 3);
    if (trns_len) chunk(&p, "tRNS", trns, trns_len);
    chunk(&p, "IDAT", idat, (uint32_t)idat_len);
    chunk(&p, "IEND", NULL, 0);
    *out_len = (size_t)(p - png);

done:
    free(pixels); free(idat);
    if (res) liq_result_destroy(res);
    if (img) liq_image_destroy(img);
    if (attr) liq_attr_destroy(attr);
    return png;
}
