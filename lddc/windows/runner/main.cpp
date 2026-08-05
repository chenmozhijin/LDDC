#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <dbghelp.h>
#include <windows.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>

#include "flutter_window.h"
#include "desktop_window_contract.h"
#include "utils.h"

namespace {

std::wstring crash_trace_path;
LONG crash_trace_written = 0;
bool crash_symbols_initialized = false;

std::wstring ReadCrashTracePath() {
  const DWORD length = ::GetEnvironmentVariableW(L"LDDC_CRASH_TRACE", nullptr, 0);
  if (length <= 1) {
    return std::wstring();
  }
  std::wstring value(length, L'\0');
  const DWORD written =
      ::GetEnvironmentVariableW(L"LDDC_CRASH_TRACE", value.data(), length);
  if (written == 0 || written >= length) {
    return std::wstring();
  }
  value.resize(written);
  return value;
}

LONG CALLBACK WriteCrashTrace(EXCEPTION_POINTERS* exception) {
  if (exception == nullptr || exception->ExceptionRecord == nullptr ||
      exception->ContextRecord == nullptr ||
      exception->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION ||
      crash_trace_path.empty() ||
      ::InterlockedCompareExchange(&crash_trace_written, 1, 0) != 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  // 只有显式设置 LDDC_CRASH_TRACE 时才启用。记录器在访问冲突的
  // 原始线程上使用异常 CONTEXT 回溯，避免只得到异常处理器自身的栈。
  std::error_code directory_error;
  const std::filesystem::path trace_path(crash_trace_path);
  std::filesystem::create_directories(trace_path.parent_path(), directory_error);
  std::ofstream output(trace_path, std::ios::out | std::ios::trunc);
  if (!output.is_open()) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  const HANDLE process = ::GetCurrentProcess();
  const HANDLE thread = ::GetCurrentThread();
  output << "exception=0x" << std::hex
         << exception->ExceptionRecord->ExceptionCode << " address=0x"
         << reinterpret_cast<uintptr_t>(
                exception->ExceptionRecord->ExceptionAddress)
         << std::dec << '\n';

  if (!crash_symbols_initialized) {
    output << "symbols unavailable" << '\n';
    output.flush();
    return EXCEPTION_CONTINUE_SEARCH;
  }

  CONTEXT context = *exception->ContextRecord;
  STACKFRAME64 frame{};
#if defined(_M_X64)
  constexpr DWORD machine_type = IMAGE_FILE_MACHINE_AMD64;
  frame.AddrPC.Offset = context.Rip;
  frame.AddrFrame.Offset = context.Rbp;
  frame.AddrStack.Offset = context.Rsp;
#elif defined(_M_IX86)
  constexpr DWORD machine_type = IMAGE_FILE_MACHINE_I386;
  frame.AddrPC.Offset = context.Eip;
  frame.AddrFrame.Offset = context.Ebp;
  frame.AddrStack.Offset = context.Esp;
#else
  constexpr DWORD machine_type = 0;
#endif
  frame.AddrPC.Mode = AddrModeFlat;
  frame.AddrFrame.Mode = AddrModeFlat;
  frame.AddrStack.Mode = AddrModeFlat;

  for (int index = 0; index < 96; ++index) {
    if (!::StackWalk64(machine_type, process, thread, &frame, &context, nullptr,
                       ::SymFunctionTableAccess64, ::SymGetModuleBase64,
                       nullptr) ||
        frame.AddrPC.Offset == 0) {
      break;
    }
    char symbol_storage[sizeof(SYMBOL_INFO) + MAX_SYM_NAME] = {};
    auto* symbol = reinterpret_cast<SYMBOL_INFO*>(symbol_storage);
    symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
    symbol->MaxNameLen = MAX_SYM_NAME;
    DWORD64 symbol_displacement = 0;
    output << '#' << index << " 0x" << std::hex << frame.AddrPC.Offset
           << std::dec;
    if (::SymFromAddr(process, frame.AddrPC.Offset, &symbol_displacement,
                      symbol)) {
      output << ' ' << symbol->Name << "+0x" << std::hex
             << symbol_displacement << std::dec;
    }
    IMAGEHLP_LINE64 line{};
    line.SizeOfStruct = sizeof(IMAGEHLP_LINE64);
    DWORD line_displacement = 0;
    if (::SymGetLineFromAddr64(process, frame.AddrPC.Offset,
                               &line_displacement, &line)) {
      output << " " << line.FileName << ':' << line.LineNumber;
    }
    output << '\n';
  }
  output.flush();
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!AttachToParentConsole() && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  crash_trace_path = ReadCrashTracePath();
  PVOID crash_handler = nullptr;
  if (!crash_trace_path.empty()) {
    ::SymSetOptions(SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES | SYMOPT_UNDNAME);
    crash_symbols_initialized =
        ::SymInitialize(::GetCurrentProcess(), nullptr, TRUE) != FALSE;
    crash_handler = ::AddVectoredExceptionHandler(1, WriteCrashTrace);
  }

  // COM 是文件对话框和若干插件能力的前置条件；初始化失败时继续启动会让
  // 后续原生 API 进入未知状态，因此这里直接失败退出。
  const HRESULT com_result =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(com_result)) {
    std::cerr << "COM 初始化失败: 0x" << std::hex << com_result << std::endl;
    return EXIT_FAILURE;
  }

  const std::wstring executable_directory = GetExecutableDirectory();
  const std::wstring flutter_data_path =
      executable_directory.empty() ? L"data" : executable_directory + L"\\data";
  flutter::DartProject project(flutter_data_path);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const bool should_start_hidden =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--not-show") != command_line_arguments.end() ||
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--get-service-port") != command_line_arguments.end();
  const bool should_show_main_window = !should_start_hidden;

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  int exit_code = EXIT_SUCCESS;
  {
    // desktop_multi_window 会延迟释放已经关闭的子 Flutter engine。主消息循环
    // 结束后，主窗口、所有子 engine 和插件必须在 COM apartment 仍有效、崩溃
    // 诊断仍可用时析构。这里的作用是固定依赖释放顺序；本次访问冲突的直接
    // 原因是 FlutterViewController 析构期间窗口消息重入，具体防护位于
    // FlutterWindow 析构函数中。
    FlutterWindow window(project, should_show_main_window);
    Win32Window::Size preferred_content_size(
        lddc::kPreferredMainWindowContentWidth,
        lddc::kPreferredMainWindowContentHeight);
    if (!window.CreateWithClientArea(L"lddc", preferred_content_size)) {
      exit_code = EXIT_FAILURE;
    } else {
      window.SetQuitOnClose(true);

      ::MSG msg;
      while (::GetMessage(&msg, nullptr, 0, 0)) {
        ::TranslateMessage(&msg);
        ::DispatchMessage(&msg);
      }
    }
  }

  if (SUCCEEDED(com_result)) {
    ::CoUninitialize();
  }
  if (crash_handler != nullptr) {
    ::RemoveVectoredExceptionHandler(crash_handler);
  }
  if (crash_symbols_initialized) {
    ::SymCleanup(::GetCurrentProcess());
  }
  return exit_code;
}
