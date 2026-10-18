#include <stdio.h>
#include <string.h>
#include "shellx_core.h"

int main(void) {
    char *out = shellx_core_call("nope", "{}");
    puts(out);
    static const char want[] = "{\"error\":{\"code\":\"unknown_method\"";
    int ok = strncmp(out, want, sizeof(want) - 1) == 0;
    shellx_core_free(out);
    return ok ? 0 : 1;
}
