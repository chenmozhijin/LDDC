cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# 主程序目标名由上层 BINARY_NAME 控制，不能在这里改名，否则 flutter run
# 和 Windows 打包产物会找不到约定的 runner。
set(LDDC_RUNNER_COMMON_SOURCES
  "desktop_panel_host_registry.cpp"
  "desktop_panel_host_plugin.cpp"
  "desktop_drag_drop_plugin.cpp"
  "desktop_window_style_plugin.cpp"
  "embedded_panel_native_host.cpp"
  "embedded_panel_channel_plugin.cpp"
  "flutter_window.cpp"
  "runner_plugin_registrant.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

add_executable(${BINARY_NAME} WIN32
  ${LDDC_RUNNER_COMMON_SOURCES}
  "main.cpp"
)

if(DEFINED LDDC_PANEL_E2E_RUNNER_TARGET)
  add_executable(${LDDC_PANEL_E2E_RUNNER_TARGET} EXCLUDE_FROM_ALL WIN32
    ${LDDC_RUNNER_COMMON_SOURCES}
    "desktop_panel_host_test_plugin.cpp"
    "panel_e2e_main.cpp"
  )
endif()

# 保留 Flutter Windows runner 的标准编译设置；如需新增 runner 专属设置，
# 应优先加在对应 target 上，避免影响 E2E 专用目标。
apply_standard_settings(${BINARY_NAME})

# Flutter 工具会注入这些版本宏，Runner.rc 和原生诊断依赖它们。
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# 避免 Windows min/max 宏污染 C++ 标准库；/utf-8 保证中文资源和日志字面量稳定。
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_compile_options(${BINARY_NAME} PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:/utf-8>")

# runner 需要 Flutter wrapper 与 DWM；新增原生依赖时应明确写在这里。
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app flutter_wrapper_plugin)
target_link_libraries(${BINARY_NAME} PRIVATE "dbghelp.lib" "dwmapi.lib" "ole32.lib" "shell32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# 该依赖负责把 Flutter 产物装配到 Windows bundle，不能删除。
add_dependencies(${BINARY_NAME} flutter_assemble)

if(TARGET ${LDDC_PANEL_E2E_RUNNER_TARGET})
  apply_standard_settings(${LDDC_PANEL_E2E_RUNNER_TARGET})
  target_compile_definitions(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
  target_compile_definitions(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
  target_compile_definitions(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
  target_compile_definitions(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
  target_compile_definitions(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
  target_compile_definitions(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "NOMINMAX")
  target_compile_definitions(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "LDDC_ENABLE_PANEL_HOST_TEST_PLUGIN=1")
  target_compile_options(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:/utf-8>")
  target_link_libraries(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE flutter flutter_wrapper_app flutter_wrapper_plugin)
  target_link_libraries(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "dwmapi.lib" "ole32.lib" "shell32.lib")
  target_include_directories(${LDDC_PANEL_E2E_RUNNER_TARGET} PRIVATE "${CMAKE_SOURCE_DIR}")
  add_dependencies(${LDDC_PANEL_E2E_RUNNER_TARGET} flutter_assemble)
  set_target_properties(${LDDC_PANEL_E2E_RUNNER_TARGET} PROPERTIES
    EXCLUDE_FROM_DEFAULT_BUILD TRUE
  )
endif()
