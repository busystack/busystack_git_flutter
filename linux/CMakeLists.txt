cmake_minimum_required(VERSION 3.24)
project(busystack_git_flutter LANGUAGES CXX)

add_subdirectory(native)
set(PLUGIN_NAME busystack_git_flutter_plugin)
add_library(${PLUGIN_NAME} SHARED busystack_git_flutter_plugin.cc)
apply_standard_settings(${PLUGIN_NAME})
target_compile_features(${PLUGIN_NAME} PRIVATE cxx_std_17)
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "$ORIGIN")
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter busystack_git_accessibility)
set(busystack_git_flutter_bundled_libraries "" PARENT_SCOPE)
