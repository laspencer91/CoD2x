#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>

namespace cod2_smoke {
// Setup commits this receipt only after installing all runtime files. Unlike
// launcher environment variables, it survives a Steam handoff/relaunch.
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
    const auto receipt = path.substr(0, slash + 1) + L"cod2-smoke-test-install.json";
    const DWORD attributes = GetFileAttributesW(receipt.c_str());
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
