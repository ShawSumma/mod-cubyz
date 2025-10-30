
#if !defined(CUBYZ_HEADER)
#define CUBYZ_HEADER
#include "mod.h"

#include "object.h"

import(cubyz, tell_user) void cubyz_tell_user(void);

static void tell_user(const char *text) {
    value(string, text);
    cubyz_tell_user();
}

#endif
