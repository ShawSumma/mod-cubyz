
#if !defined(OBJECT_HEADER)
#define OBJECT_HEADER
#include "mod.h"

// get size of value stack
import(object, get_mark) int system_mark(void);

// push simple value to stack
import(object, push_u8) void system_push_u8(uint32_t x);
import(object, push_u16) void system_push_u16(uint32_t x);
import(object, push_u32) void system_push_u32(uint32_t x);
import(object, push_u64) void system_push_u64(uint64_t x);

import(object, push_i8) void system_push_i8(int32_t x);
import(object, push_i16) void system_push_i16(int32_t x);
import(object, push_i32) void system_push_i32(int32_t x);
import(object, push_i64) void system_push_i64(int64_t x);

import(object, push_f32) void system_push_f32(float x);
import(object, push_f64) void system_push_f64(double x);

// push value to stack from last `n` stack items
import(object, make_list) void system_make_list(int start, int end);
import(object, make_string) void system_make_string(int start, int end);
import(object, make_map) void system_make_map(int start, int end);

static void system_push_string(const char *text) {
    int start = system_mark();
    for (int i = 0; text[i] != '\0'; i++) {
        system_push_u8(text[i]);
    }
    system_make_string(start, system_mark());
}

#define check_eq(a, b) ((a) == (b) ? __builtin_trap() : 0)
#define value(t, v) system_push_ ## t(v)
#define list for(int start_ = system_mark(), loop_ = 0; loop_ != 0 ? (system_make_list(start_, system_mark()), 0) : 1; loop_++)
#define map for(int start_ = system_mark(), loop_ = 0; loop_ != 0 ? (system_make_map(start_, system_mark()), 0) : 1; loop_++)
#define key(name) for(int start_ = (system_push_string(#name), system_mark()), loop_ = 0; loop_ != 0 ? (check_eq(start_, system_mark()), 0) : 1; loop_++)
#define on_init export(on_init) void init(void)
#define on_command(name) __attribute__((visibility("default"), export_name("on_command_" #name))) void command_ ## name()

#endif
