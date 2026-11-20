// Shrinks a picture to a palette PNG, the way pngquant does, using pngquant's engine (libimagequant, GPL v3).
#ifndef PNGShrink_h
#define PNGShrink_h

#include <stddef.h>

/// `rgba`: width*height*4 bytes, sRGB, straight (not premultiplied) alpha.
/// `min_quality`/`max_quality`: 0-100, as pngquant's --quality; when the engine can't reach `min_quality` it gives up.
/// `dpi`: written as the PNG's pixel density when above 0 (Retina screenshots are 144).
/// Returns a malloc'd PNG (free it) and its size in `out_len`, or NULL.
unsigned char *us_shrink_png(const unsigned char *rgba, int width, int height,
                             int min_quality, int max_quality, double dpi, size_t *out_len);

#endif
