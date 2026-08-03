#include <flutter/dart_project.h>
#include <windows.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include "flutter_window.h"
#include "desktop_window_contract.h"
#include "utils.h"

namespace {

std::wstring ResolveReportDirectory(
    const std::vector<std::string>& command_line_arguments) {
  constexpr wchar_t kFallbackReportDir[] = L"build\\panel_e2e_reports";
  constexpr const char kPrefix[] = "--report-dir=";
  for (const std::string& argument : command_line_arguments) {
    if (argument.rfind(kPrefix, 0) != 0) {
      continue;
    }
    const std::string path = argument.substr(sizeof(kPrefix) - 1);
    if (path.empty()) {
      continue;
    }
    return std::filesystem::path(path.begin(), path.end()).wstring();
  }
  return kFallbackReportDir;
}

void WriteBootstrapTrace(const std::wstring& report_directory,
                         const std::string& stage,
                         const std::string& detail = std::string()) {
  if (report_directory.empty()) {
    return;
  }
  std::error_code error;
  std::filesystem::create_directories(report_directory, error);
  const std::filesystem::path trace_path =
      std::filesystem::path(report_directory) / "native_bootstrap.log";
  std::ofstream stream(trace_path, std::ios::out | std::ios::app);
  if (!stream.is_open()) {
    return;
  }
  stream << stage;
  if (!detail.empty()) {
    stream << " " << detail;
  }
  stream << "\n";
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (!AttachToParentConsole() && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  const std::wstring report_directory =
      ResolveReportDirectory(command_line_arguments);
  WriteBootstrapTrace(report_directory, "native_entry_entered");

  const HRESULT com_result =
      ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(com_result)) {
    std::ostringstream detail;
    detail << "hresult=0x" << std::hex << com_result;
    WriteBootstrapTrace(report_directory, "com_initialize_failed",
                        detail.str());
    std::cerr << "COM 初始化失败: " << detail.str() << std::endl;
    return EXIT_FAILURE;
  }

  const std::wstring executable_directory = GetExecutableDirectory();
  const std::wstring flutter_data_path =
      executable_directory.empty() ? L"data" : executable_directory + L"\\data";
  flutter::DartProject project(flutter_data_path);
  project.set_dart_entrypoint("panelE2EMain");

  const bool should_show_main_window =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--not-show") == command_line_arguments.end();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
  WriteBootstrapTrace(report_directory, "project_configured");

  FlutterWindow window(project, should_show_main_window);
  Win32Window::Size preferred_content_size(
      lddc::kPreferredMainWindowContentWidth,
      lddc::kPreferredMainWindowContentHeight);
  if (!window.CreateWithClientArea(L"lddc_panel_e2e",
                                   preferred_content_size)) {
    WriteBootstrapTrace(report_directory, "window_create_failed");
    return EXIT_FAILURE;
  }
  WriteBootstrapTrace(report_directory, "window_create_succeeded");
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  WriteBootstrapTrace(report_directory, "message_loop_exited");

  if (SUCCEEDED(com_result)) {
    ::CoUninitialize();
  }
  return static_cast<int>(msg.wParam);
}
