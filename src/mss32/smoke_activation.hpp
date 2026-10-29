#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>

namespace cod2_smoke {
// ProSmoke is active when its runtime folder sits beside the game executable. A plain
// file copy installs it and deleting the folder removes it; no receipt or registry.
// Unlike launcher environment variables, this survives a Steam handoff/relaunch.
inline bool installed_preview() {
#ifndef COD2X_SMOKE_TEST_BUILD
    return false;
#else
    wchar_t executable[MAX_PATH]{};
    const DWORD length = GetModuleFileNameW(nullptr, executable, MAX_PATH);
    if (!length || length >= MAX_PATH) return false;
    const std::wstring path(executable, length);
    const auto slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return false;
    const auto runtime = path.substr(0, slash + 1) + L"prosmoke\\prosmoke.dll";
    const DWORD attributes = GetFileAttributesW(runtime.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES
        && !(attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT));
#endif
}

inline bool activation_flag(const char* name, bool installed) {
#ifndef COD2X_SMOKE_TEST_BUILD
    return false;
#else
    char setting[8]{};
    SetLastError(ERROR_SUCCESS);
    const DWORD length = GetEnvironmentVariableA(name, setting, sizeof(setting));
    if (!length && GetLastError() == ERROR_ENVVAR_NOT_FOUND) return installed;
    // Explicit overrides are retained for renderer diagnostics and opt-out.
    return length == 1 && setting[0] == '1';
#endif
}
}
