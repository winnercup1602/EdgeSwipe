#ifndef MTLayout_h
#define MTLayout_h

#include <stddef.h>
#include <stdint.h>

// The empirically observed arm64 MultitouchSupport contact ABI.
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t path;
    uint32_t state;
    int32_t finger;
    int32_t hand;
    float x, y, dx, dy;
    float size;
    int32_t pressureBits;
    float angle, majorAxis, minorAxis;
    float absolute[4];
    int32_t reserved[2];
    float density;
} ESContact;

_Static_assert(sizeof(ESContact) == 96, "Unexpected contact stride");
_Static_assert(offsetof(ESContact, state) == 20, "Unexpected state offset");
_Static_assert(offsetof(ESContact, x) == 32, "Unexpected coordinates offset");

#endif
