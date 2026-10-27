// SPDX-License-Identifier: GPL-3.0-or-later
// Local build/install handshake. Never executes caller-supplied console text.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include "../shared/shared.h"
#include "../shared/cod2_dvars.h"
#include "../shared/cod2_client.h"
#include "../shared/cod2_cmd.h"
#include "../shared/cod2_file.h"
#include "mapkit_reload.h"

namespace {
namespace fs = std::filesystem;
enum class Phase { Idle, Disconnecting, Released, Loading };
Phase phase = Phase::Idle;
bool initialized = false, disabled = false;
bool resume_game = false;
fs::path directory;
char token[33]{}, request_id[33]{}, target[33]{}, mode[16]{"tdm"};
const char* failure = "";
DWORD last_poll = 0, phase_time = 0;
constexpr DWORD poll_ms = 100, disconnect_ms = 15000, lease_ms = 60000;

bool hex_id(const char* text) {
    return std::strlen(text) == 32 && std::strspn(text, "0123456789abcdef") == 32;
}
bool map_id(const char* text) {
    if (!text) return false;
    const size_t n = std::strlen(text);
    return n >= 4 && n <= 31 && std::strncmp(text, "mp_", 3) == 0
        && std::strspn(text, "abcdefghijklmnopqrstuvwxyz0123456789_") == n;
}
bool game_mode(const char* text) {
    if (!text) return false;
    for (const auto* item : {"tdm", "sd", "dm", "ctf", "hq"})
        if (std::strcmp(item, text) == 0) return true;
    return false;
}
bool local_session() {
    return clientState == CLIENT_STATE_DISCONNECTED
        || (sv_running && sv_running->value.boolean);
}
bool same_directory(const fs::path& a, const char* b) {
    std::error_code error;
    const auto canonical = fs::weakly_canonical(fs::path(b ? b : ""), error);
    return !error && _stricmp(a.string().c_str(), canonical.string().c_str()) == 0;
}
void publish() {
    const char* state = *failure ? "error" : phase == Phase::Disconnecting ? "disconnecting"
        : phase == Phase::Released ? "released" : phase == Phase::Loading ? "loading"
        : clientState == CLIENT_STATE_ACTIVE ? "active" : "idle";
    const char* current_map = Dvar_GetString("mapname");
    const char* current_mode = Dvar_GetString("g_gametype");
    char text[512]{};
    std::snprintf(text, sizeof(text),
        "{\"version\":1,\"pid\":%lu,\"session\":\"%s\",\"request\":\"%s\",\"state\":\"%s\",\"clientState\":%d,\"map\":\"%s\",\"mode\":\"%s\",\"error\":\"%s\"}\n",
        GetCurrentProcessId(), token, request_id, state, int(clientState),
        map_id(current_map) ? current_map : "", game_mode(current_mode) ? current_mode : "tdm", failure);
    const auto temporary = directory / "status.next";
    { std::ofstream output(temporary, std::ios::binary | std::ios::trunc); output << text; }
    MoveFileExW(temporary.c_str(), (directory / "status.json").c_str(), MOVEFILE_REPLACE_EXISTING);
}
void remount(bool load) {
    Dvar_SetString(Dvar_GetDvarByName("fs_game"), "mapkit");
    FS_Restart(0);
    if (load) {
        // Request a render-thread grid refresh even when reloading the same map name.
        using Refresh = void(__cdecl*)();
        const auto renderer = GetModuleHandleA("mapkit_smoke.dll");
        const auto refresh = renderer ? reinterpret_cast<Refresh>(GetProcAddress(renderer, "Smoke_MapReload")) : nullptr;
        if (refresh) refresh();
        char command[128]{};
        std::snprintf(command, sizeof(command), "set g_gametype %s\ndevmap %s\n", mode, target);
        Cbuf_AddText(command);
        phase = Phase::Loading;
    } else phase = Phase::Idle;
    phase_time = GetTickCount();
}
void initialize() {
    char enabled[8]{};
    if (GetEnvironmentVariableA("COD2_MAPKIT_RELOAD", enabled, sizeof(enabled)) != 1 || enabled[0] != '1'
        || GetEnvironmentVariableA("COD2_MAPKIT_RELOAD_TOKEN", token, sizeof(token)) != 32 || !hex_id(token)) {
        disabled = true; return;
    }
    // These dvars are not initialized on the earliest CL_Init callback.
    if (!Dvar_GetDvarByName("fs_game") || !sv_running || !dedicated) return;
    wchar_t executable[MAX_PATH]{};
    const DWORD length = GetModuleFileNameW(nullptr, executable, MAX_PATH);
    if (!length || length >= MAX_PATH) { disabled = true; return; }
    const auto root = fs::weakly_canonical(fs::path(executable).parent_path());
    if (dedicated->value.integer || std::strcmp(Dvar_GetString("fs_game"), "mapkit") != 0
        || !same_directory(root, Dvar_GetString("fs_basepath"))
        || !same_directory(root, Dvar_GetString("fs_homepath"))) { disabled = true; return; }
    directory = root / "mapkit-control";
    std::error_code error; fs::create_directories(directory, error);
    if (error) { disabled = true; return; }
    initialized = true;
}
void request() {
    const auto path = directory / "request.txt";
    std::error_code error;
    const auto size = fs::file_size(path, error);
    if (error || size > 256) return;
    std::ifstream input(path, std::ios::binary);
    char text[257]{}; input.read(text, sizeof(text) - 1); input.close();
    char version[8]{}, key[34]{}, id[34]{}, operation[16]{}, map[34]{}, gametype[16]{}, extra[2]{};
    if (std::sscanf(text, "%7s %33s %33s %15s %33s %15s %1s", version, key, id, operation, map, gametype, extra) != 6
        || std::strcmp(version, "v1") || std::strcmp(key, token) || !hex_id(id)
        || !map_id(map) || !game_mode(gametype) || !std::strcmp(id, request_id)) return;
    fs::remove(path, error);
    std::strcpy(request_id, id); failure = "";
    if (!local_session()) { failure = "remote_session"; return; }
    if (!std::strcmp(operation, "release") && phase != Phase::Disconnecting && phase != Phase::Loading) {
        const char* mod = Dvar_GetString("fs_game");
        if (std::strcmp(mod, "mapkit") && phase != Phase::Released) { failure = "different_mod"; return; }
        std::strcpy(target, map); std::strcpy(mode, gametype);
        resume_game = clientState == CLIENT_STATE_ACTIVE;
        phase = Phase::Disconnecting; phase_time = GetTickCount();
        Cbuf_AddText("disconnect\nkillserver\n");
    } else if ((!std::strcmp(operation, "load") || !std::strcmp(operation, "mount")) && phase == Phase::Released) {
        std::strcpy(target, map); std::strcpy(mode, gametype);
        remount(!std::strcmp(operation, "load"));
    } else failure = "invalid_phase";
}
}

void mapkit_reload_frame() {
    if (disabled) return;
    try {
        if (!initialized) { initialize(); if (!initialized) return; }
        const DWORD now = GetTickCount();
        if (now - last_poll < poll_ms) return;
        last_poll = now;
        request();
        // A request may just have advanced phase_time. Sample after it so unsigned
        // elapsed time cannot underflow and report an immediate timeout.
        const DWORD state_now = GetTickCount();
        if (phase == Phase::Disconnecting) {
            if (clientState == CLIENT_STATE_DISCONNECTED && !sv_running->value.boolean) {
                Dvar_SetString(Dvar_GetDvarByName("fs_game"), "");
                FS_Restart(0); // remount main only, releasing all mod IWD handles
                phase = Phase::Released; phase_time = GetTickCount();
            } else if (state_now - phase_time > disconnect_ms) { failure = "disconnect_timeout"; phase = Phase::Idle; }
        } else if (phase == Phase::Released && state_now - phase_time > lease_ms) {
            remount(resume_game); // recovery if Map Kit is cancelled/crashes after disconnect
        } else if (phase == Phase::Loading && clientState == CLIENT_STATE_ACTIVE) phase = Phase::Idle;
        publish();
    } catch (...) { failure = "bridge_io_error"; }
}
