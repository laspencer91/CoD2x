// Copyright (c) 2026 Logan Spencer. Private preview.
// CoD2x adapter diagnostics; offsets are pinned in integration-targets.json.
#include "smoke_diagnostics.h"
#include "mapkit_reload.h"
#include "smoke_activation.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>
#include <openssl/evp.h>

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <initializer_list>
#include <cstddef>
#include <algorithm>
#include <string>
#include "../shared/shared.h"
#include "../shared/assembly.h"
#include "../shared/cod2_entity.h"
#include "../shared/cod2_dvars.h"
#include "../shared/cod2_common.h"
#include "../shared/cod2_cmd.h"
#include "policy.hpp"

namespace {
constexpr char kRendererName[] = "gfx_d3d_mp_x86_s.dll";
constexpr char kRendererHash[] = "243505f56ec0f86122fc09b3a6c18f0daf49a00abb2d969147f595991584a6b2";
constexpr uintptr_t kRenderSceneRva = 0x25b90;
constexpr uintptr_t kRenderSceneSlot = 0x68a27c;
constexpr uintptr_t kDeviceRva = 0x1d1bf8;
constexpr uintptr_t kFloatZRva = 0x1d4898;
constexpr uintptr_t kZFeatherRva = 0x1ce694;
constexpr DWORD kLogLimit = 2 * 1024 * 1024;
constexpr DWORD kLogIntervalMs = 1000;
constexpr uintptr_t kResolvedBulletCall = 0x5277e7;
constexpr uintptr_t kBulletNotify = 0x523ed0;
constexpr uintptr_t kServerRunningDvar = 0xc26108;
constexpr uintptr_t kServerWeaponOffset = offsetof(gentity_t, s) + offsetof(entityState_t, weapon);
static_assert(kServerWeaponOffset == 200, "pinned CoD2 server weapon layout");
bool trace_installed = false;
bool install_trace();
bool restore_trace();
bool resolved_impact(int shooter, const float* end);
bool forward_bullet(int shooter, int weapon, const float* start, const float* end, const char* source);
struct ResolvedEnd { float point[3]{}; DWORD tick = 0; };
ResolvedEnd resolved_ends[64][32]{};
unsigned resolved_next[64]{};

struct Refdef {
    int x, y, width, height;
    float fov_x, fov_y;
    float eye[3], axis[3][3];
    int time, flags;
    unsigned char area_mask[8];
};
struct FloatZTarget {
    void* image;
    IDirect3DSurface9* color;
    IDirect3DSurface9* depth;
    unsigned width, height;
};
static_assert(sizeof(void*) == 4, "CoD2 is a 32-bit process");
static_assert(sizeof(Refdef) == 88, "CoD2 refdef layout");
static_assert(sizeof(FloatZTarget) == 20, "CoD2 render target layout");
using RenderScene = void (__cdecl*)(const Refdef*);

HANDLE log_file = INVALID_HANDLE_VALUE;
uintptr_t renderer = 0;
RenderScene original_scene = nullptr;
bool renderer_verified = false;
bool log_started = false;
DWORD last_sample = 0;
unsigned scene_count = 0;
using SetSmokeView = void (__cdecl*)(const Refdef*);
SetSmokeView set_smoke_view = nullptr;
using WantsBullets = bool (__cdecl*)();
using Bullet = void (__cdecl*)(int, int, const char*, const float*, const float*, int);
WantsBullets wants_bullets = nullptr;
Bullet smoke_bullet = nullptr;
HMODULE smoke_module = nullptr;
using SmokeSettings = void (__cdecl*)(const char*, unsigned, bool);
SmokeSettings smoke_settings = nullptr;
using PopConsole = int (__cdecl*)(char*, unsigned);
PopConsole pop_console = nullptr;     // renderer status lines for the game console
using SmokeStatus = int (__cdecl*)(char*, unsigned);
SmokeStatus smoke_status = nullptr;   // one-line summary for prosmoke_status
const char* resolution_names[]{"full", "half", "quarter", nullptr};
dvar_t* smoke_resolution = nullptr;

template<typename T> T procedure(HMODULE module, const char* name) {
    const auto address = module ? GetProcAddress(module, name) : nullptr;
    T result = nullptr;
    static_assert(sizeof(result) == sizeof(address), "Win32 function pointer size");
    std::memcpy(&result, &address, sizeof(result));
    return result;
}

bool enabled() {
    static const bool value = cod2_smoke::activation_flag("COD2_SMOKE_DIAGNOSTICS", cod2_smoke::installed_preview());
    return value;
}

bool readable(const void* address, size_t bytes) {
    const uintptr_t start = reinterpret_cast<uintptr_t>(address);
    if (!start || bytes > UINTPTR_MAX - start) return false;
    uintptr_t cursor = start;
    const uintptr_t end = start + bytes;
    while (cursor < end) {
        MEMORY_BASIC_INFORMATION info = {};
        if (!VirtualQuery(reinterpret_cast<void*>(cursor), &info, sizeof(info))
            || info.State != MEM_COMMIT || (info.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
        const DWORD access = info.Protect & 0xff;
        if (access != PAGE_READONLY && access != PAGE_READWRITE && access != PAGE_WRITECOPY
            && access != PAGE_EXECUTE_READ && access != PAGE_EXECUTE_READWRITE
            && access != PAGE_EXECUTE_WRITECOPY) return false;
        const uintptr_t next = reinterpret_cast<uintptr_t>(info.BaseAddress) + info.RegionSize;
        if (next <= cursor) return false;
        cursor = next;
    }
    return true;
}

template<typename T> bool read(uintptr_t address, T& value) {
    if (!readable(reinterpret_cast<void*>(address), sizeof(T))) return false;
    std::memcpy(&value, reinterpret_cast<void*>(address), sizeof(T));
    return true;
}

void log(const char* format, ...) {
    if (log_file == INVALID_HANDLE_VALUE) return;
    LARGE_INTEGER size = {};
    if (!GetFileSizeEx(log_file, &size) || size.QuadPart >= kLogLimit - 2048) return;
    char line[2048];
    int prefix = std::snprintf(line, sizeof(line), "[%lu] ", static_cast<unsigned long>(GetTickCount()));
    va_list args;
    va_start(args, format);
    std::vsnprintf(line + prefix, sizeof(line) - prefix - 2, format, args);
    va_end(args);
    size_t length = std::strlen(line);
    line[length++] = '\r';
    line[length++] = '\n';
    DWORD written = 0;
    WriteFile(log_file, line, static_cast<DWORD>(length), &written, nullptr);
}

void start_log() {
    if (log_started) return;
    log_started = true;
    wchar_t path[MAX_PATH] = {};
    DWORD length = GetEnvironmentVariableW(L"COD2_SMOKE_LOG", path, MAX_PATH);
    if (length >= MAX_PATH) return;
    if (!length) {
        length = GetEnvironmentVariableW(L"LOCALAPPDATA", path, MAX_PATH);
        if (!length || length >= MAX_PATH) return;
        std::wstring directory(path, length);
        for (const auto* component : {L"\\prosmoke"}) {
            directory += component;
            if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return;
        }
        const auto filename = directory + L"\\bridge.log";
        if (filename.size() >= MAX_PATH) return;
        std::copy(filename.begin(), filename.end(), path);
        path[filename.size()] = 0;
    }
    log_file = CreateFileW(path, FILE_APPEND_DATA | FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    log("begin adapter=smoke installed_preview=%d process=%lu stock_fx=preserved_until_ready",
        int(cod2_smoke::installed_preview()), static_cast<unsigned long>(GetCurrentProcessId()));
}

bool verify_renderer(HMODULE module) {
    char path[MAX_PATH] = {};
    DWORD length = GetModuleFileNameA(module, path, sizeof(path));
    if (!length || length >= sizeof(path)) return false;
    HANDLE input = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    if (input == INVALID_HANDLE_VALUE) return false;
    EVP_MD_CTX* context = EVP_MD_CTX_new();
    if (!context || EVP_DigestInit_ex(context, EVP_sha256(), nullptr) != 1) {
        EVP_MD_CTX_free(context);
        CloseHandle(input);
        return false;
    }
    unsigned char buffer[16384], digest[32] = {};
    DWORD count = 0;
    bool ok = true;
    for (;;) {
        if (!ReadFile(input, buffer, sizeof(buffer), &count, nullptr)) { ok = false; break; }
        if (!count) break;
        if (EVP_DigestUpdate(context, buffer, count) != 1) { ok = false; break; }
    }
    CloseHandle(input);
    unsigned digest_size = 0;
    ok = EVP_DigestFinal_ex(context, digest, &digest_size) == 1 && digest_size == sizeof(digest) && ok;
    EVP_MD_CTX_free(context);
    char hash[sizeof(digest) * 2 + 1] = {};
    for (size_t i = 0; i < sizeof(digest); ++i) std::sprintf(hash + i * 2, "%02x", digest[i]);
    log("renderer_file=%s sha256=%s read_ok=%d", path, hash, ok);
    return ok && std::strcmp(hash, kRendererHash) == 0;
}

bool com_method(void* object, size_t slot) {
    uintptr_t vtable = 0, method = 0;
    if (!read(reinterpret_cast<uintptr_t>(object), vtable)
        || !read(vtable + slot * sizeof(void*), method)) return false;
    MEMORY_BASIC_INFORMATION info = {};
    if (!VirtualQuery(reinterpret_cast<void*>(method), &info, sizeof(info))
        || info.State != MEM_COMMIT || (info.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
    return (info.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE
        | PAGE_EXECUTE_WRITECOPY)) != 0;
}

void sample(const Refdef* view) {
    const DWORD now = GetTickCount();
    if (scene_count++ && now - last_sample < kLogIntervalMs) return;
    last_sample = now;
    Refdef camera = {};
    if (!read(reinterpret_cast<uintptr_t>(view), camera)) { log("refdef=unreadable"); return; }
    log("scene=%u time=%d viewport=%d,%d,%d,%d fov=%.3f,%.3f eye=%.3f,%.3f,%.3f axis=%.3f,%.3f,%.3f;%.3f,%.3f,%.3f;%.3f,%.3f,%.3f",
        scene_count, camera.time, camera.x, camera.y, camera.width, camera.height,
        camera.fov_x, camera.fov_y, camera.eye[0], camera.eye[1], camera.eye[2],
        camera.axis[0][0], camera.axis[0][1], camera.axis[0][2], camera.axis[1][0],
        camera.axis[1][1], camera.axis[1][2], camera.axis[2][0], camera.axis[2][1], camera.axis[2][2]);

    uintptr_t feather = 0;
    unsigned char feather_value = 0;
    const bool feather_ok = read(renderer + kZFeatherRva, feather) && read(feather + 8, feather_value);
    FloatZTarget target = {};
    const bool target_ok = read(renderer + kFloatZRva, target);
    log("zfeather_known=%d enabled=%u floatz_known=%d image=%p color=%p depth=%p dimensions=%ux%u freshness=unverified",
        feather_ok, feather_value, target_ok, target.image, target.color, target.depth, target.width, target.height);
    D3DSURFACE_DESC description = {};
    if (target_ok && com_method(target.color, 12)) {
        const HRESULT result = target.color->GetDesc(&description);
        log("floatz_surface hr=0x%08lx format=%u usage=0x%lx pool=%u dimensions=%ux%u multisample=%u",
            static_cast<unsigned long>(result), description.Format, description.Usage,
            description.Pool, description.Width, description.Height, description.MultiSampleType);
    }
    IDirect3DTexture9* texture = nullptr;
    if (target_ok && read(reinterpret_cast<uintptr_t>(target.image) + 4, texture)
        && com_method(texture, 17)) {
        const HRESULT result = texture->GetLevelDesc(0, &description);
        log("floatz_texture=%p hr=0x%08lx format=%u dimensions=%ux%u", texture,
            static_cast<unsigned long>(result), description.Format, description.Width, description.Height);
    }
    IDirect3DDevice9* device = nullptr;
    D3DCAPS9 caps = {};
    if (read(renderer + kDeviceRva, device) && com_method(device, 7)) {
        const HRESULT result = device->GetDeviceCaps(&caps);
        log("device=%p hr=0x%08lx pixel_shader=0x%lx max_volume=%lu volume_filter_caps=0x%lx",
            device, static_cast<unsigned long>(result), caps.PixelShaderVersion,
            caps.MaxVolumeExtent, caps.VolumeTextureFilterCaps);
    }
}

// The policy this client currently sees. Systeminfo (1) comes from servers that register
// the dvar; stock CoD2x servers cannot, so serverinfo (0), published with `sets`, is next.
std::string replicated_policy() {
    const auto replicated = [](int index) {
        const char* info = nullptr;
        ASM_CALL(RETURN(info), 0x4020d0, 0, EAX(index));
        return info ? cod2_smoke::policy_from_info(std::string_view(info, strnlen(info, 16384))) : std::string{};
    };
    auto policy = replicated(1);
    if (policy.empty()) policy = replicated(0);
    return policy;
}

void __cdecl scene(const Refdef* view) {
    // R_RenderScene submits work; this sample does NOT prove a current-frame depth pass.
    if (original_scene) {
        sample(view);
        if (smoke_settings) {
            // CL_GetConfigString owns a bounded, NUL-terminated engine string.
            // Do not VirtualQuery once per character on this per-view path.
            const auto policy = replicated_policy();
            static const bool developer_opt_in = [] {
                char dev[8]{};
                return GetEnvironmentVariableA("COD2_SMOKE_DEV", dev, sizeof(dev)) == 1 && dev[0] == '1';
            }();
            const bool developer = developer_opt_in
                && sv_running && sv_running->value.boolean && Dvar_GetBool("sv_cheats");
            const int selection = smoke_resolution ? smoke_resolution->value.integer : 1;
            smoke_settings(policy.c_str(), selection == 0 ? 1 : selection == 2 ? 4 : 2, developer);
            if (pop_console) {
                // Renderer status lines, printed on the engine thread that owns the console.
                char line[512];
                for (int i = 0; i < 8 && pop_console(line, sizeof(line)) > 0; ++i) Com_Printf("^3ProSmoke:^7 %s\n", line);
            }
        }
        if (set_smoke_view) set_smoke_view(view);
        original_scene(view);
    }
}

bool exchange_scene(RenderScene expected, RenderScene replacement) {
    DWORD protection = 0;
    auto slot = reinterpret_cast<void* volatile*>(kRenderSceneSlot);
    if (!VirtualProtect(reinterpret_cast<void*>(kRenderSceneSlot), sizeof(void*), PAGE_READWRITE, &protection)) return false;
    void* previous = InterlockedCompareExchangePointer(slot,
        reinterpret_cast<void*>(replacement), reinterpret_cast<void*>(expected));
    DWORD ignored = 0;
    VirtualProtect(reinterpret_cast<void*>(kRenderSceneSlot), sizeof(void*), protection, &ignored);
    return previous == reinterpret_cast<void*>(expected);
}
} // namespace

void smoke_diagnostics_startup() {
    if (!enabled()) return;
    start_log();
    log("startup render_enabled=%d awaiting_renderer=1", int(cod2_smoke::activation_flag(
        "COD2_SMOKE_RENDER", cod2_smoke::installed_preview())));
}

void smoke_diagnostics_renderer_loaded() {
    if (!enabled()) return;
    start_log();
    // Logging is best-effort: an unwritable or invalid path must not disable smoke.
    original_scene = nullptr;
    renderer_verified = false;
    HMODULE module = GetModuleHandleA(kRendererName);
    renderer = reinterpret_cast<uintptr_t>(module);
    if (!module || !verify_renderer(module)) { log("renderer=rejected no_hook_installed"); return; }
    renderer_verified = true;
    if (cod2_smoke::activation_flag("COD2_SMOKE_RENDER", cod2_smoke::installed_preview())) {
        char path[MAX_PATH] = {};
        const DWORD length = GetModuleFileNameA(nullptr, path, sizeof(path));
        char* slash = std::strrchr(path, '\\');
        if (length && length < sizeof(path) && slash && static_cast<size_t>(slash - path) + 40 < sizeof(path)) {
            std::strcpy(slash + 1, "prosmoke\\prosmoke.dll");
            if (!smoke_module) smoke_module = LoadLibraryExA(path, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
            using Initialize = bool (__cdecl*)(uintptr_t);
            auto init = procedure<Initialize>(smoke_module, "Smoke_Init");
            if (init && init(renderer)) {
                set_smoke_view = procedure<SetSmokeView>(smoke_module, "Smoke_SetView");
                wants_bullets = procedure<WantsBullets>(smoke_module, "Smoke_WantsBullets");
                smoke_bullet = procedure<Bullet>(smoke_module, "Smoke_Bullet");
                smoke_settings = procedure<SmokeSettings>(smoke_module, "Smoke_Settings");
                pop_console = procedure<PopConsole>(smoke_module, "Smoke_PopConsole");
                smoke_status = procedure<SmokeStatus>(smoke_module, "Smoke_Status");
            }
            log("smoke_renderer=%p camera_callback=%p error=%lu", smoke_module, reinterpret_cast<void*>(set_smoke_view), GetLastError());
        }
    } else log("smoke_renderer=disabled_by_activation");
    scene_count = 0;
    last_sample = 0;
    // Record loaded instruction bytes only; never detour the packed executable's FX paths.
    for (uintptr_t address : {uintptr_t(0x499570), uintptr_t(0x499740), uintptr_t(0x4e0980)}) {
        unsigned char bytes[16] = {};
        char hex[33] = {};
        if (!read(address, bytes)) continue;
        for (size_t i = 0; i < sizeof(bytes); ++i) std::sprintf(hex + i * 2, "%02x", bytes[i]);
        log("loaded_code address=0x%08lx bytes=%s abi=unverified", static_cast<unsigned long>(address), hex);
    }
    log("renderer=verified base=%p awaiting_export_table", module);
}

// /prosmoke_status: what the loader, the server policy and the renderer currently report.
void prosmoke_status_command() {
    if (!smoke_module) {
        Com_Printf("ProSmoke: renderer not loaded. prosmoke\\prosmoke.dll must sit beside CoD2MP_s.exe; see %%LOCALAPPDATA%%\\prosmoke\\bridge.log\n");
        return;
    }
    const auto policy = replicated_policy();
    Com_Printf("ProSmoke: renderer loaded; server policy %s\n", policy.empty() ? "not set (normal smoke)" : policy.c_str());
    char text[1024] = {};
    if (smoke_status && smoke_status(text, sizeof(text)) > 0) Com_Printf("ProSmoke: %s\n", text);
    else Com_Printf("ProSmoke: renderer has not drawn a frame yet\n");
    const int selection = smoke_resolution ? smoke_resolution->value.integer : 1;
    Com_Printf("ProSmoke: quality %s (prosmoke_resolution full|half|quarter)\n", resolution_names[selection >= 0 && selection < 3 ? selection : 1]);
}

void smoke_diagnostics_register_settings() {
    smoke_resolution = Dvar_RegisterEnum(cod2_smoke::resolution_dvar, resolution_names, 1, DVAR_ARCHIVE);
    Cmd_AddCommand("prosmoke_status", prosmoke_status_command);
}

void smoke_diagnostics_frame() {
    mapkit_reload_frame();
    if (!enabled() || !renderer_verified) return;
    if (smoke_bullet && !trace_installed) install_trace();
    if (original_scene) return;
    RenderScene current = nullptr;
    const auto expected = reinterpret_cast<RenderScene>(renderer + kRenderSceneRva);
    if (!read(kRenderSceneSlot, current) || current != expected) return;
    original_scene = expected;
    if (!exchange_scene(expected, scene)) { original_scene = nullptr; return; }
    log("scene_export=wrapped slot=0x%08lx target=%p", static_cast<unsigned long>(kRenderSceneSlot), reinterpret_cast<void*>(expected));
}

bool smoke_diagnostics_shutdown() {
    if (!restore_trace()) { log("shutdown=deferred could_not_restore_bullet_call"); return false; }
    wants_bullets = nullptr; smoke_bullet = nullptr; smoke_settings = nullptr; set_smoke_view = nullptr;
    pop_console = nullptr; smoke_status = nullptr;
    RenderScene current = nullptr;
    if (original_scene && read(kRenderSceneSlot, current) && current == scene
        && !exchange_scene(scene, original_scene)) {
        log("shutdown=deferred could_not_restore_scene_export");
        return false;
    }
    original_scene = nullptr;
    renderer_verified = false;
    log("end stock_fx=preserved");
    if (log_file != INVALID_HANDLE_VALUE) CloseHandle(log_file);
    log_file = INVALID_HANDLE_VALUE;
    return true;
}

bool smoke_diagnostics_wants_bullets() {
    return renderer_verified && smoke_bullet && wants_bullets && wants_bullets();
}

void smoke_diagnostics_bullet(int shooter, int weapon, const float* start, const float* end) {
    // The listen server supplies exact resolved segments, including misses. Do
    // not carve those shots a second time when their impact event arrives.
    if (resolved_impact(shooter, end)) return;
    forward_bullet(shooter, weapon, start, end, "impact");
}

namespace {
bool resolved_impact(int shooter, const float* end) {
    uintptr_t dvar = 0; unsigned char running = 0;
    if (!trace_installed || shooter < 0 || shooter >= 64 || !read(kServerRunningDvar, dvar)
        || !read(dvar + 8, running) || !running) return false;
    const DWORD now = GetTickCount();
    for (auto& known : resolved_ends[shooter]) {
        if (!known.tick || now - known.tick > 500) continue;
        float distance = 0;
        for (int axis = 0; axis < 3; ++axis) { const float delta = known.point[axis] - end[axis]; distance += delta * delta; }
        if (distance <= 9) { known.tick = 0; return true; } // One-to-one quantized network impact match.
    }
    return false;
}

bool forward_bullet(int shooter, int weapon, const float* start, const float* end, const char* source) {
    if (!smoke_diagnostics_wants_bullets() || weapon <= 0 || weapon > 255) return false;
    uintptr_t definition = 0, name = 0;
    char text[64] = {};
    int time = 0;
    // Weapon table and client clock from the pinned engine's CG_FireWeapon path.
    if (!read(0x1728200 + weapon * sizeof(uintptr_t), definition) || !read(definition, name)
        || !read(0x1513c30, time)) return false;
    if (!readable(reinterpret_cast<const void*>(name), sizeof(text) - 1)) return false;
    std::memcpy(text, reinterpret_cast<const void*>(name), sizeof(text) - 1);
    smoke_bullet(shooter, weapon, text, start, end, time);
    static unsigned samples = 0;
    if (samples++ < 32)
        log("bullet source=%s shooter=%d weapon=%d name=%s start=%.2f,%.2f,%.2f end=%.2f,%.2f,%.2f time=%d",
            source, shooter, weapon, text, start[0], start[1], start[2], end[0], end[1], end[2], time);
    return true;
}

int __cdecl resolved_notify(void* attacker, const float* end, int damage, int kind) {
    const float* start; ASM__movr(start, "ecx");
    if (smoke_diagnostics_wants_bullets()) {
        int shooter = -1, weapon = 0; float a[3]{}, b[3]{};
        const auto entity = reinterpret_cast<uintptr_t>(attacker);
        if (read(entity, shooter) && shooter >= 0 && shooter < 64 && read(entity + kServerWeaponOffset, weapon)
            && read(reinterpret_cast<uintptr_t>(start), a) && read(reinterpret_cast<uintptr_t>(end), b))
            if (forward_bullet(shooter, weapon, a, b, "resolved")) {
                auto& known = resolved_ends[shooter][resolved_next[shooter]++ % 32];
                std::memcpy(known.point, b, sizeof(b)); known.tick = GetTickCount();
            }
    }
    // Preserve the original notify/gameplay behavior and its ECX + four-stack-argument ABI.
    ASM_CALL_RETURN(int, kBulletNotify, 4, ECX(start), PUSH(attacker), PUSH(end), PUSH(damage), PUSH(kind));
}

bool change_trace(uintptr_t expected, uintptr_t replacement) {
    unsigned char code[5]{};
    if (!read(kResolvedBulletCall, code) || code[0] != 0xe8) return false;
    int32_t relative = 0; std::memcpy(&relative, code + 1, sizeof(relative));
    if (kResolvedBulletCall + 5 + relative != expected) return false;
    const auto offset = static_cast<int32_t>(replacement - kResolvedBulletCall - 5);
    std::memcpy(code + 1, &offset, sizeof(offset));
    DWORD protection = 0, ignored = 0;
    auto* address = reinterpret_cast<void*>(kResolvedBulletCall);
    if (!VirtualProtect(address, sizeof(code), PAGE_EXECUTE_READWRITE, &protection)) return false;
    std::memcpy(address, code, sizeof(code));
    FlushInstructionCache(GetCurrentProcess(), address, sizeof(code));
    VirtualProtect(address, sizeof(code), protection, &ignored);
    return true;
}
bool install_trace() {
    trace_installed = change_trace(kBulletNotify, reinterpret_cast<uintptr_t>(&resolved_notify));
    static bool reported_failure = false;
    if (trace_installed) log("resolved_bullet=wrapped call=0x%08lx local_server_only=1", static_cast<unsigned long>(kResolvedBulletCall));
    else if (!reported_failure) { log("resolved_bullet=unavailable impact_fallback_retained"); reported_failure = true; }
    return trace_installed;
}
bool restore_trace() {
    if (!trace_installed) return true;
    if (!change_trace(reinterpret_cast<uintptr_t>(&resolved_notify), kBulletNotify)) return false;
    trace_installed = false;
    return true;
}
}
