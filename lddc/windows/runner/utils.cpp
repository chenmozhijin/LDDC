#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>
#include <vector>

namespace {

bool IsRedirectedHandle(DWORD std_handle) {
  HANDLE handle = ::GetStdHandle(std_handle);
  if (handle == nullptr || handle == INVALID_HANDLE_VALUE) {
    return false;
  }
  DWORD file_type = ::GetFileType(handle);
  return file_type == FILE_TYPE_PIPE || file_type == FILE_TYPE_DISK;
}

bool ShouldPreserveStdHandles() {
  return IsRedirectedHandle(STD_OUTPUT_HANDLE) ||
         IsRedirectedHandle(STD_ERROR_HANDLE);
}

void BindWin32ConsoleHandles() {
  HANDLE console_out = ::CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                                     FILE_SHARE_READ | FILE_SHARE_WRITE,
                                     nullptr, OPEN_EXISTING,
                                     FILE_ATTRIBUTE_NORMAL, nullptr);
  if (console_out != INVALID_HANDLE_VALUE) {
    ::SetStdHandle(STD_OUTPUT_HANDLE, console_out);
    ::SetStdHandle(STD_ERROR_HANDLE, console_out);
  }

  HANDLE console_in = ::CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE,
                                    FILE_SHARE_READ | FILE_SHARE_WRITE,
                                    nullptr, OPEN_EXISTING,
                                    FILE_ATTRIBUTE_NORMAL, nullptr);
  if (console_in != INVALID_HANDLE_VALUE) {
    ::SetStdHandle(STD_INPUT_HANDLE, console_in);
  }
}

void RedirectConsoleStreams() {
  if (ShouldPreserveStdHandles()) {
    return;
  }
  BindWin32ConsoleHandles();
  FILE *unused;
  if (freopen_s(&unused, "CONOUT$", "w", stdout) == 0) {
    _dup2(_fileno(stdout), 1);
  }
  if (freopen_s(&unused, "CONOUT$", "w", stderr) == 0) {
    _dup2(_fileno(stderr), 2);
  }
  std::ios::sync_with_stdio();
  FlutterDesktopResyncOutputStreams();
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    RedirectConsoleStreams();
  }
}

bool AttachToParentConsole() {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS)) {
    return false;
  }
  RedirectConsoleStreams();
  return true;
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::wstring GetExecutableDirectory() {
  std::vector<wchar_t> buffer(MAX_PATH, L'\0');
  while (true) {
    if (buffer.size() > static_cast<size_t>(MAXDWORD)) {
      return std::wstring();
    }
    const DWORD copied =
        ::GetModuleFileNameW(nullptr, buffer.data(),
                             static_cast<DWORD>(buffer.size()));
    if (copied == 0) {
      return std::wstring();
    }
    if (copied < buffer.size() - 1) {
      std::wstring path(buffer.data(), copied);
      const std::wstring::size_type separator = path.find_last_of(L"\\/");
      if (separator == std::wstring::npos) {
        return std::wstring();
      }
      return path.substr(0, separator);
    }
    buffer.resize(buffer.size() * 2, L'\0');
  }
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  const int required_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string, -1, nullptr, 0, nullptr,
      nullptr);
  // WideCharToMultiByte 失败时返回 0；必须先判断再减去结尾 null，
  // 否则 unsigned 下溢会把错误路径变成巨大字符串分配。
  if (required_length <= 1) {
    return std::string();
  }
  const size_t target_length = static_cast<size_t>(required_length - 1);
  const int input_length = static_cast<int>(wcslen(utf16_string));
  std::string utf8_string;
  if (target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  const int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), static_cast<int>(target_length),
      nullptr, nullptr);
  if (converted_length <= 0) {
    return std::string();
  }
  return utf8_string;
}
