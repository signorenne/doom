cmake_minimum_required(VERSION 3.25)

project({{PROJECT}}
    VERSION     0.1.0
    DESCRIPTION "{{PROJECT}}: a C++23 application"
    HOMEPAGE_URL "https://github.com/{{GITHUB_USER}}/{{PROJECT}}"
    LANGUAGES   CXX
)

set(CMAKE_CXX_STANDARD            23)
set(CMAKE_CXX_STANDARD_REQUIRED   ON)
set(CMAKE_CXX_EXTENSIONS          OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

option({{PROJECT_UPPER}}_BUILD_TESTS        "Build the unit tests"              ${PROJECT_IS_TOP_LEVEL})
option({{PROJECT_UPPER}}_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

include(GNUInstallDirs)
include({{PROJECT}}_warnings)

# The logic lives in a library so the tests can link it; main.cpp only wires
# the program together.
add_library({{PROJECT}}_core INTERFACE)
add_library({{PROJECT}}::core ALIAS {{PROJECT}}_core)

file(GLOB_RECURSE {{PROJECT_UPPER}}_HEADERS
    CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/include/*.hpp"
)

target_sources({{PROJECT}}_core INTERFACE
    FILE_SET {{PROJECT}}_headers TYPE HEADERS
    BASE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/include
    FILES ${{{PROJECT_UPPER}}_HEADERS}
)
target_compile_features({{PROJECT}}_core INTERFACE cxx_std_23)

add_executable({{PROJECT}} src/main.cpp)
target_link_libraries({{PROJECT}}
    PRIVATE
        {{PROJECT}}::core
        {{PROJECT}}::warnings
)

if({{PROJECT_UPPER}}_BUILD_TESTS)
    include({{PROJECT}}_testing)
    enable_testing()
    add_subdirectory(tests)
endif()

install(TARGETS {{PROJECT}} RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

message(STATUS "[{{PROJECT}}] v${PROJECT_VERSION} tests=${{{PROJECT_UPPER}}_BUILD_TESTS} "
               "werror=${{{PROJECT_UPPER}}_WARNINGS_AS_ERRORS}")
