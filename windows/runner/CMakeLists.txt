cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# ============================================================
# 拷贝 Node.js 运行时和猫影视项目到可执行文件旁
# 目的：让 Release 目录自带 Node 环境，无需用户单独安装
# 入口文件兼容 main.js / index.js（与 iOS NodeJSManager.m 兜底一致）
# ============================================================
set(NODEJS_SRC_DIR "${CMAKE_SOURCE_DIR}/nodejs")
set(NODEJS_DST_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>/nodejs")

if(NOT EXISTS "${NODEJS_SRC_DIR}/runtime/node.exe")
    message(FATAL_ERROR "[NodeJS] 缺少 ${NODEJS_SRC_DIR}/runtime/node.exe")
endif()

if(EXISTS "${NODEJS_SRC_DIR}/project/dist/main.js")
    set(NODEJS_ENTRY "main.js")
elseif(EXISTS "${NODEJS_SRC_DIR}/project/dist/index.js")
    set(NODEJS_ENTRY "index.js")
else()
    message(FATAL_ERROR "[NodeJS] 缺少 ${NODEJS_SRC_DIR}/project/dist/{main.js|index.js}")
endif()

message(STATUS "[NodeJS] 使用入口: ${NODEJS_ENTRY}")

add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${NODEJS_SRC_DIR}/runtime"
        "${NODEJS_DST_DIR}/runtime"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${NODEJS_SRC_DIR}/project"
        "${NODEJS_DST_DIR}/project"
    COMMENT "[NodeJS] 拷贝 runtime 和 project 到 ${NODEJS_DST_DIR}"
)