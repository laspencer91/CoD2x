// Executable Windows x86 fixture for the actual production short-wait header.
#include "../../src/mss32/smoke_waits.hpp"
#include <cstdio>
#include <stdexcept>
#include <vector>
using namespace cod2_smoke::short_waits;
static_assert(sizeof(void*)==4,"native x86 ABI fixture");
void require(bool ok,const char* text){if(!ok)throw std::runtime_error(text);}
DWORD forwarded_delay=99;unsigned forwarded=0;
void WINAPI spy(DWORD delay){forwarded_delay=delay;++forwarded;}
void WINAPI foreign(DWORD){}
struct Fixture {
    unsigned char* memory=nullptr;
    uintptr_t base=0;
    static constexpr uintptr_t import=0x1000,caller=0x2008;
    Fixture(){memory=static_cast<unsigned char*>(VirtualAlloc(nullptr,0x4000,MEM_RESERVE|MEM_COMMIT,PAGE_EXECUTE_READWRITE));require(memory,"allocate fixture");base=reinterpret_cast<uintptr_t>(memory);
        IMAGE_DOS_HEADER dos{};dos.e_magic=IMAGE_DOS_SIGNATURE;dos.e_lfanew=0x100;std::memcpy(memory,&dos,sizeof(dos));
        IMAGE_NT_HEADERS32 nt{};nt.Signature=IMAGE_NT_SIGNATURE;nt.FileHeader.Machine=IMAGE_FILE_MACHINE_I386;nt.OptionalHeader.Magic=IMAGE_NT_OPTIONAL_HDR32_MAGIC;nt.OptionalHeader.SizeOfImage=0x4000;std::memcpy(memory+0x100,&nt,sizeof(nt));
        auto fn=spy;std::memcpy(memory+import,&fn,sizeof(fn));
        const unsigned char code[]{0x6a,0x01,0xff,0x15,0,0,0,0,0xc3};std::memcpy(memory+caller-8,code,sizeof(code));
        const uint32_t slot=uint32_t(base+import);std::memcpy(memory+caller-4,&slot,4);
        FlushInstructionCache(GetCurrentProcess(),memory,0x4000);
        DWORD old=0;require(VirtualProtect(memory+import,0x1000,PAGE_READONLY,&old)!=FALSE,"protect fixture import");}
    ~Fixture(){if(memory)VirtualFree(memory,0,MEM_RELEASE);}
    SleepFn current(){SleepFn result;std::memcpy(&result,memory+import,sizeof(result));return result;}
    void call(){reinterpret_cast<void(*)()>(base+caller-8)();}
};
int main(){try{
    require(!active.load()&&!configured.load(),"defaults must leave native waits");
    require(!install(GetModuleHandleW(nullptr),GetModuleHandleW(nullptr))&&!game.slot&&!render.slot,"foreign executable must not change imports");
    require(!game_signature(0)&&!render_signature(0),"invalid image pointer must reject without dereference");
    const unsigned char hello[]{'h','e','l','l','o'};require(fingerprint(hello,5)==0xa430d84680aabd0bULL,"fingerprint");
    Fixture a,b;require(image_bounds(a.base,0x4000)&&!image_bounds(a.base,0x4001),"image bounds");
    native_sleep=spy;
    require(install_context(game,a.base,Fixture::import,Fixture::caller,game_hook),"install game fixture");
    require(install_context(render,b.base,Fixture::import,Fixture::caller,render_hook),"install render fixture");
    require(a.current()==game_hook&&b.current()==render_hook,"exact hook addresses");
    MEMORY_BASIC_INFORMATION region{};VirtualQuery(a.memory+Fixture::import,&region,sizeof(region));require(region.Protect==PAGE_READONLY,"import protection restored");
    require(install_context(game,a.base,Fixture::import,Fixture::caller,game_hook),"same renderer reinstall idempotent");
    configured=true;healthy=true;set_active(false);a.call();require(forwarded_delay==1&&!game.calls.load(),"inactive routes original");
    set_active(true);game_hook(0);render_hook(7);require(forwarded_delay==7&&!game.calls.load()&&!render.calls.load(),"foreign caller/argument forwarding");
    for(unsigned i=0;i<32;++i){a.call();b.call();}
    require(game.calls.load()==32&&render.calls.load()==32&&!game.fallbacks.load()&&!render.fallbacks.load(),"real timer and x86 return-address routing");
    require(!matches(game,reinterpret_cast<void*>(a.base+Fixture::caller+1),1)&&!matches(game,reinterpret_cast<void*>(a.base+Fixture::caller),0),"exact caller/delay guards");
    game.busy.test_and_set();const unsigned before=forwarded;a.call();game.busy.clear();
    require(forwarded==before+1&&forwarded_delay==1&&!healthy.load()&&!active.load()&&game.fallbacks.load()==1,"contention falls back without crash");
    healthy=true;set_active(true);CloseHandle(render.timer);render.timer=nullptr;b.call();
    require(!healthy.load()&&!active.load()&&render.fallbacks.load()==1&&forwarded_delay==1,"timer failure preserves native sleep");
    require(exchange(a.base+Fixture::import,game_hook,foreign),"insert foreign fixture import");
    require(!restore_context(game,game_hook)&&a.current()==foreign,"restore must not overwrite foreign hooks");
    require(exchange(a.base+Fixture::import,foreign,game_hook),"restore fixture hook");
    require(restore()&&a.current()==spy&&b.current()==spy,"exact import restoration");
    const auto calls=game.calls.load();game_hook(1);require(game.calls.load()==calls&&forwarded_delay==1,"cached hook remains safe after restore");
    if(game.timer)CloseHandle(game.timer);
    std::puts("PASS production short waits: foreign images/bounds/signatures reject; original forwarding; real x86 caller routes and64 blocked timers; protection/idempotence; contention/timer fallback; foreign-hook ownership; exact restore/cached forwarding");return 0;
}catch(const std::exception& error){std::fprintf(stderr,"FAIL %s\n",error.what());return 1;}}
