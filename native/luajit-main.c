/* Embed the Lua CLI in a native Windows entry point, without a shell wrapper. */
#include <stdio.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include "table-script.h"

int main(int argc, char **argv) {
    lua_State *state = luaL_newstate();
    if (!state) { fputs("table: cannot initialize LuaJIT\n", stderr); return 1; }
    luaL_openlibs(state);
    lua_createtable(state, argc, 0);
    for (int i = 0; i < argc; i++) {
        lua_pushstring(state, argv[i]);
        lua_rawseti(state, -2, i);
    }
    lua_setglobal(state, "arg");
    int failed = luaL_loadbuffer(state, (const char *)table_script_lua,
        table_script_lua_len, "table") || lua_pcall(state, 0, 0, 0);
    if (failed) fprintf(stderr, "table: %s\n", lua_tostring(state, -1));
    lua_close(state);
    return failed ? 1 : 0;
}
