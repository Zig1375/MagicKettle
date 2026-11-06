// Stands in for Windows PowerShell where Wine has only a stub that runs nothing and prints nothing.
//
// Programs ask PowerShell for registry values: r2modman finds Steam with
//   powershell.exe "Get-ItemProperty -Path HKLM:\SOFTWARE\WOW6432Node\Valve\Steam -Name "InstallPath""
// and with Wine's stub it got no answer and said "Unable to resolve steam install folder", so no mod could be
// started. This answers `Get-ItemProperty` the way PowerShell prints it ("Name : value" lines) and fails anything
// else plainly, with PowerShell's exit code for an error.
//
// Build: scripts/build-powershell.sh (needs `brew install mingw-w64`).
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <wctype.h>

// Magic Kettle tells its stand-in from Wine's stub by this text (`PowerShell.marker`).
__attribute__((used)) static const char marker[] = "magickettle-powershell/1";

// The command line without the program's own name.
static const wchar_t *arguments(void) {
    const wchar_t *rest = GetCommandLineW();
    if (*rest == L'"') {
        rest++;
        while (*rest && *rest != L'"') rest++;
        if (*rest) rest++;
    } else {
        while (*rest && *rest != L' ' && *rest != L'\t') rest++;
    }
    return rest;
}

// Case-insensitive search.
static const wchar_t *find(const wchar_t *text, const wchar_t *word) {
    size_t length = wcslen(word);
    for (; *text; text++) {
        if (_wcsnicmp(text, word, length) == 0) return text;
    }
    return NULL;
}

// The value after a parameter such as `-Path`: up to the closing quote when quoted, else up to a space.
static BOOL parameter(const wchar_t *command, const wchar_t *name, wchar_t *out, size_t size) {
    const wchar_t *at = find(command, name);
    if (!at) return FALSE;
    at += wcslen(name);
    while (*at == L' ' || *at == L'\t') at++;
    wchar_t quote = (*at == L'"' || *at == L'\'') ? *at++ : 0;
    size_t used = 0;
    while (*at && used + 1 < size) {
        if (quote ? *at == quote : (*at == L' ' || *at == L'\t' || *at == L'"' || *at == L'\'')) break;
        out[used++] = *at++;
    }
    out[used] = 0;
    return used > 0;
}

// `HKLM:\SOFTWARE\…`, `HKEY_LOCAL_MACHINE\…` or `Registry::HKEY_…\…` as a root key and its subkey.
static BOOL split(const wchar_t *path, HKEY *root, const wchar_t **subkey) {
    static const struct { const wchar_t *name; HKEY key; } roots[] = {
        {L"HKLM:", HKEY_LOCAL_MACHINE}, {L"HKCU:", HKEY_CURRENT_USER},
        {L"HKEY_LOCAL_MACHINE", HKEY_LOCAL_MACHINE}, {L"HKEY_CURRENT_USER", HKEY_CURRENT_USER},
        {L"HKEY_CLASSES_ROOT", HKEY_CLASSES_ROOT}, {L"HKEY_USERS", HKEY_USERS},
    };
    if (_wcsnicmp(path, L"Registry::", 10) == 0) path += 10;
    for (size_t i = 0; i < sizeof(roots) / sizeof(roots[0]); i++) {
        size_t length = wcslen(roots[i].name);
        if (_wcsnicmp(path, roots[i].name, length) == 0) {
            path += length;
            while (*path == L'\\' || *path == L'/') path++;
            *root = roots[i].key;
            *subkey = path;
            return TRUE;
        }
    }
    return FALSE;
}

static void print(const wchar_t *name, DWORD type, const BYTE *data, DWORD size) {
    if (type == REG_SZ || type == REG_EXPAND_SZ) {
        wprintf(L"%-12ls : %.*ls\r\n", name, (int)(size / sizeof(wchar_t)), (const wchar_t *)data);
    } else if (type == REG_DWORD && size >= sizeof(DWORD)) {
        wprintf(L"%-12ls : %lu\r\n", name, *(const DWORD *)data);
    } else if (type == REG_QWORD && size >= sizeof(ULONGLONG)) {
        wprintf(L"%-12ls : %llu\r\n", name, *(const ULONGLONG *)data);
    }
}

static int getItemProperty(const wchar_t *command) {
    wchar_t path[1024] = {0}, name[256] = {0};
    if (!parameter(command, L"-Path", path, 1024)) return 1;
    BOOL named = parameter(command, L"-Name", name, 256);
    HKEY root;
    const wchar_t *subkey;
    if (!split(path, &root, &subkey)) return 1;
    HKEY key;
    if (RegOpenKeyExW(root, subkey, 0, KEY_READ, &key) != ERROR_SUCCESS) {
        fwprintf(stderr, L"Get-ItemProperty : Cannot find path '%ls' because it does not exist.\r\n", path);
        return 1;
    }
    static BYTE data[65536];
    wchar_t value[16384];
    wprintf(L"\r\n");
    if (named) {
        DWORD type, size = sizeof(data) - sizeof(wchar_t);
        if (RegQueryValueExW(key, name, NULL, &type, data, &size) != ERROR_SUCCESS) {
            RegCloseKey(key);
            fwprintf(stderr, L"Get-ItemProperty : Property %ls does not exist at path %ls.\r\n", name, path);
            return 1;
        }
        print(name, type, data, size);
    } else {
        for (DWORD index = 0;; index++) {
            DWORD length = 16384, type, size = sizeof(data) - sizeof(wchar_t);
            if (RegEnumValueW(key, index, value, &length, NULL, &type, data, &size) != ERROR_SUCCESS) break;
            print(value[0] ? value : L"(default)", type, data, size);
        }
    }
    wprintf(L"\r\n");
    RegCloseKey(key);
    return 0;
}

int wmain(void) {
    // `\"` is a quote too: the C runtime's way of writing one inside a quoted argument.
    static wchar_t command[32768];
    size_t used = 0;
    for (const wchar_t *at = arguments(); *at && used + 1 < 32768; at++) {
        if (at[0] == L'\\' && at[1] == L'"') continue;
        command[used++] = *at;
    }
    command[used] = 0;
    if (find(command, L"Get-ItemProperty")) {
        return getItemProperty(command);
    }
    fwprintf(stderr, L"PowerShell can't run this here: %ls\r\n", command);
    return 1;
}
