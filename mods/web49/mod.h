
#if !defined(MOD_HEADER)
#define MOD_HEADER

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#define export(name) __attribute__((visibility("default"), export_name(#name)))
#define import(api, name) __attribute__((import_module(#api), import_name(#name)))

#endif
