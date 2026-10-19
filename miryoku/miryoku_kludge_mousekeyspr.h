// Copyright 2022 Manna Harbour
// https://github.com/manna-harbour/miryoku

#pragma once

// Upstream ZMK merged feat/pointers-move-scroll and renamed these from
// ZMK_MOUSE_DEFAULT_* to ZMK_POINTING_DEFAULT_* (dt-bindings/zmk/pointing.h).
// Define both so this header works against either vintage; pointing.h guards
// its own defaults with #ifndef, and is included after this file.
//
// These are the top speeds. With scroll at EXPONENT 0 the value applies from
// the first instant, so it doubles as both per-tap distance and hold rate:
// Miryoku's traditional 100 (live via U_MOUSE_SCROLL_MAX before upstream
// 7e46baf) is jumpy per tap, while 12 was unusably slow. 60 sits between.
#define ZMK_MOUSE_DEFAULT_MOVE_VAL 2000
#define ZMK_MOUSE_DEFAULT_SCRL_VAL 60
#define ZMK_POINTING_DEFAULT_MOVE_VAL 2000
#define ZMK_POINTING_DEFAULT_SCRL_VAL 60

// Speed = MOVE_VAL * (held_time / TIME) ^ EXPONENT, capped at MOVE_VAL.
//
// EXPONENT is uint8 and the base is < 1, so a HIGHER exponent starts slower
// (ZMK: 0 = uniform speed, 1 = uniform acceleration, 2 = uniform jerk). There
// is no fractional/sharp-off-the-line curve available, so 1 stays: it's the
// only value that accelerates smoothly at all. Snappiness comes from the short
// TIME instead — acceleration is still present, it just resolves quickly.
#define U_MOUSE_MOVE_EXPONENT 1
#define U_MOUSE_MOVE_TIME 250
#define U_MOUSE_MOVE_DELAY 0
// Scroll uses EXPONENT 0 (uniform speed): scrolling is discrete notches, so a
// ramp makes a single tap imperceptible and then overshoots as it accelerates.
// Every tap now emits the same notch, and holding repeats at a steady rate.
#define U_MOUSE_SCROLL_EXPONENT 0
#define U_MOUSE_SCROLL_TIME 250
#define U_MOUSE_SCROLL_DELAY 0

#define U_BTN1 &mkp MB1
#define U_BTN2 &mkp MB2
#define U_BTN3 &mkp MB3
#define U_MS_D &mmv MOVE_DOWN
#define U_MS_L &mmv MOVE_LEFT
#define U_MS_R &mmv MOVE_RIGHT
#define U_MS_U &mmv MOVE_UP
#define U_WH_D &msc SCRL_DOWN
#define U_WH_L &msc SCRL_LEFT
#define U_WH_R &msc SCRL_RIGHT
#define U_WH_U &msc SCRL_UP
