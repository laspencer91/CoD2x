// Copyright (c) 2026 Logan Spencer. Private preview.
// Short blocked waits for the two verified native GPU fence Sleep(1) callers.
// Fence tests, prediction limits and all other Sleep calls remain native.
#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <atomic>
#include <cstdint>
#include <cstring>
#if defined(_MSC_VER)
#include <intrin.h>
#define PROSMOKE_WAIT_NOINLINE __declspec(noinline)
#define PROSMOKE_WAIT_CALLER _ReturnAddress()
#else
#define PROSMOKE_WAIT_NOINLINE __attribute__((noinline))
#define PROSMOKE_WAIT_CALLER __builtin_return_address(0)
#pragma GCC push_options
#pragma GCC optimize ("O2")
#endif

namespace cod2_smoke::short_waits {
using SleepFn = void (WINAPI*)(DWORD);
using CreateTimer = HANDLE (WINAPI*)(LPSECURITY_ATTRIBUTES,LPCWSTR,DWORD,DWORD);
inline constexpr unsigned delay_us = 250;
inline constexpr uintptr_t game_entry = 0x12670, game_return = 0x126a8, game_import = 0x1931c4;
inline constexpr uintptr_t render_return = 0x332dd, render_import = 0x10c07c;
struct Context {
    uintptr_t slot = 0;
    std::atomic<uintptr_t> caller{0};
    HANDLE timer = nullptr;
    std::atomic_flag busy = ATOMIC_FLAG_INIT;
    std::atomic<uint64_t> calls{0}, fallbacks{0};
};
inline Context game, render;
inline SleepFn native_sleep = ::Sleep;
inline std::atomic<bool> configured{false}, healthy{true}, active{false};
inline const char* reason = "not installed";

template<class T> inline T procedure(const char* name) {
    const auto address=GetProcAddress(GetModuleHandleW(L"kernel32.dll"),name);
    T result=nullptr;static_assert(sizeof(result)==sizeof(address));
    std::memcpy(&result,&address,sizeof(result));return result;
}

inline bool readable(uintptr_t address, size_t bytes) {
    if (!address || bytes > UINTPTR_MAX-address) return false;
    const auto end=address+bytes;
    while(address<end){MEMORY_BASIC_INFORMATION region{};
        if(!VirtualQuery(reinterpret_cast<void*>(address),&region,sizeof(region)) || region.State!=MEM_COMMIT ||
            (region.Protect&(PAGE_NOACCESS|PAGE_GUARD)))return false;
        const auto next=reinterpret_cast<uintptr_t>(region.BaseAddress)+region.RegionSize;
        if(next<=address)return false;
        address=next;
    }return true;
}
inline bool image_bounds(uintptr_t base, size_t required) {
    IMAGE_DOS_HEADER dos{};IMAGE_NT_HEADERS32 nt{};
    if(!readable(base,sizeof(dos)))return false;
    std::memcpy(&dos,reinterpret_cast<void*>(base),sizeof(dos));
    if(dos.e_magic!=IMAGE_DOS_SIGNATURE || dos.e_lfanew<0 || dos.e_lfanew>0x100000 ||
        base>UINTPTR_MAX-uintptr_t(dos.e_lfanew)-sizeof(nt) || !readable(base+dos.e_lfanew,sizeof(nt)))return false;
    std::memcpy(&nt,reinterpret_cast<void*>(base+dos.e_lfanew),sizeof(nt));
    return nt.Signature==IMAGE_NT_SIGNATURE && nt.FileHeader.Machine==IMAGE_FILE_MACHINE_I386 &&
        nt.OptionalHeader.Magic==IMAGE_NT_OPTIONAL_HDR32_MAGIC && nt.OptionalHeader.SizeOfImage>=required &&
        required<=UINTPTR_MAX-base;
}
inline uint64_t fingerprint(const unsigned char* bytes,size_t count) {
    uint64_t hash=14695981039346656037ULL;
    for(size_t i=0;i<count;++i)hash=(hash^bytes[i])*1099511628211ULL;
    return hash;
}
inline bool game_signature(uintptr_t base) {
    return base==0x400000 && image_bounds(base,game_import+sizeof(void*)) && readable(base+game_entry,0x49) &&
        fingerprint(reinterpret_cast<const unsigned char*>(base+game_entry),0x49)==0xb39a9efa136e187bULL;
}
inline bool render_signature(uintptr_t base) {
    if(!image_bounds(base,render_import+sizeof(void*)) || !readable(base+0x33293,0x50))return false;
    const unsigned char load[]{0x8b,0x3d}, loop[]{0x6a,0x01,0xff,0xd7,0xeb,0xc1};uint32_t slot=0;
    std::memcpy(&slot,reinterpret_cast<void*>(base+0x33295),4);
    return !std::memcmp(reinterpret_cast<void*>(base+0x33293),load,sizeof(load)) && slot==base+render_import &&
        !std::memcmp(reinterpret_cast<void*>(base+0x332d9),loop,sizeof(loop));
}
inline bool exchange(uintptr_t address,SleepFn expected,SleepFn replacement) {
    if(!readable(address,sizeof(void*)))return false;
    DWORD protection=0;
    if(!VirtualProtect(reinterpret_cast<void*>(address),sizeof(void*),PAGE_READWRITE,&protection))return false;
    const auto previous=InterlockedCompareExchangePointer(reinterpret_cast<void* volatile*>(address),
        reinterpret_cast<void*>(replacement),reinterpret_cast<void*>(expected));
    DWORD ignored=0;const bool restored=VirtualProtect(reinterpret_cast<void*>(address),sizeof(void*),protection,&ignored)!=FALSE;
    return previous==reinterpret_cast<void*>(expected) && restored;
}
inline bool matches(const Context& context,const void* caller,DWORD delay) {
    return delay==1 && reinterpret_cast<uintptr_t>(caller)==context.caller.load(std::memory_order_relaxed);
}
inline void route(Context& context,const void* caller,DWORD delay) {
    if(!matches(context,caller,delay) || !active.load(std::memory_order_relaxed)){native_sleep(delay);return;}
    if(context.busy.test_and_set(std::memory_order_acquire)){
        ++context.fallbacks;healthy=false;active=false;native_sleep(delay);return;
    }
    LARGE_INTEGER due{};due.QuadPart=-LONGLONG(delay_us)*10;
    if(context.timer && SetWaitableTimer(context.timer,&due,0,nullptr,nullptr,FALSE) &&
        WaitForSingleObject(context.timer,16)==WAIT_OBJECT_0)++context.calls;
    else {++context.fallbacks;healthy=false;active=false;native_sleep(delay);}
    context.busy.clear(std::memory_order_release);
}
PROSMOKE_WAIT_NOINLINE inline void WINAPI game_hook(DWORD delay) { route(game,PROSMOKE_WAIT_CALLER,delay); }
PROSMOKE_WAIT_NOINLINE inline void WINAPI render_hook(DWORD delay) { route(render,PROSMOKE_WAIT_CALLER,delay); }

inline bool install_context(Context& context,uintptr_t base,uintptr_t import,uintptr_t caller,SleepFn hook) {
    const uintptr_t slot=base+import;
    if(!readable(slot,sizeof(void*)))return false;
    SleepFn current=nullptr;std::memcpy(&current,reinterpret_cast<void*>(slot),sizeof(current));
    if(current==hook && context.slot==slot)return true;
    if(current!=native_sleep)return false;
    if(!context.timer){
        const auto create=procedure<CreateTimer>("CreateWaitableTimerExW");
        if(!create)return false;
        context.timer=create(nullptr,nullptr,0x2,TIMER_MODIFY_STATE|SYNCHRONIZE);
        if(!context.timer)return false;
    }
    context.caller.store(base+caller,std::memory_order_relaxed);
    context.slot=slot;
    if(!exchange(slot,native_sleep,hook)){
        SleepFn after=nullptr;std::memcpy(&after,reinterpret_cast<void*>(slot),sizeof(after));
        if(after!=hook)context.slot=0;
        return false;
    }
    return true;
}
inline bool restore_context(Context& context,SleepFn hook) {
    if(!context.slot)return true;
    SleepFn current=nullptr;
    if(!readable(context.slot,sizeof(current)))return false;
    std::memcpy(&current,reinterpret_cast<void*>(context.slot),sizeof(current));
    if(current!=native_sleep && !exchange(context.slot,hook,native_sleep))return false;
    context.slot=0;return true;
}
inline bool install(HMODULE engine,HMODULE renderer) {
    active=false;configured=false;
#if defined(DEBUG) && DEBUG
    // The release loader stays loaded for the process lifetime. Debug hot reload
    // can unload cached function pointers, so leave native imports in that build.
    (void)engine;(void)renderer;reason="disabled for debug hot reload";return false;
#else
    const auto front=reinterpret_cast<uintptr_t>(engine),back=reinterpret_cast<uintptr_t>(renderer);
    if(!game_signature(front) || !render_signature(back)){reason="unsupported native code signature";return false;}
    const auto system_sleep=procedure<SleepFn>("Sleep");
    if(!system_sleep){reason="native Sleep unavailable";return false;}
    // Assign only before the first hook is installed. Later renderer reloads
    // can overlap a cached hook forwarding an unrelated Sleep call.
    if(!game.slot && !render.slot)native_sleep=system_sleep;
    else if(native_sleep!=system_sleep){reason="native Sleep changed";return false;}
    if(!install_context(game,front,game_import,game_return,game_hook)){
        restore_context(game,game_hook);
        reason="game import or high-resolution timer unavailable";return false;
    }
    if(!install_context(render,back,render_import,render_return,render_hook)){
        restore_context(game,game_hook);reason="renderer import or high-resolution timer unavailable";return false;
    }
    configured=true;reason="native fence checks preserved";return true;
#endif
}
inline void set_active(bool enabled) { active.store(enabled && configured.load() && healthy.load(),std::memory_order_relaxed); }
inline bool restore() {
    active=false;configured=false;
    const bool front=restore_context(game,game_hook),back=restore_context(render,render_hook);
    // Keep timers for any in-flight hook or renderer-cached Sleep function.
    // Windows owns their final cleanup when the release client exits.
    return front && back;
}
}
#if !defined(_MSC_VER)
#pragma GCC pop_options
#endif
#undef PROSMOKE_WAIT_NOINLINE
#undef PROSMOKE_WAIT_CALLER
