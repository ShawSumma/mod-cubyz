
#include "object.h"
#include "cubyz.h"

on_command(test) {
    tell_user("ran test command");
}

on_init {
    list {
        for (int i = 0; i < 10; i++) {
            value(i32, i);
        }
        value(string, "hello world");
    }
    map {
        key(foo) {
            value(i32, 0);
        }
    }
}
