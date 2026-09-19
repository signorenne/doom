cmake_minimum_required(VERSION 3.25)

project({{PROJECT}}
    VERSION     0.1.0
    DESCRIPTION "{{PROJECT}}: a C++23 library"
    HOMEPAGE_URL "https://github.com/{{GITHUB_USER}}/{{PROJECT}}"
    LANGUAGES   CXX
)

set(CMAKE_CXX_STANDARD            23)
set(CMAKE_CXX_STANDARD_REQUIRED   ON)
set(CMAKE_CXX_EXTENSIONS          OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Off by default for a consumer that adds this project with add_subdirectory.
option({{PROJECT_UPPER}}_BUILD_TESTS        "Build the unit tests"              ${PROJECT_IS_TOP_LEVEL})
option({{PROJECT_UPPER}}_BUILD_EXAMPLES     "Build the example programs"        ${PROJECT_IS_TOP_LEVEL})
option({{PROJECT_UPPER}}_INSTALL            "Generate the install rules"        ${PROJECT_IS_TOP_LEVEL})
option({{PROJECT_UPPER}}_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)
include({{PROJECT}}_warnings)

# Header-only: the target carries the includes, nothing is compiled. The file
# set is what install() copies, and it is globbed so the filesystem stays the
# only registry of the public surface.
add_library({{PROJECT}} INTERFACE)
add_library({{PROJECT}}::{{PROJECT}} ALIAS {{PROJECT}})

file(GLOB_RECURSE {{PROJECT_UPPER}}_HEADERS
    CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/include/*.hpp"
)

target_sources({{PROJECT}} INTERFACE
    FILE_SET {{PROJECT}}_headers TYPE HEADERS
    BASE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/include
    FILES ${{{PROJECT_UPPER}}_HEADERS}
)
target_compile_features({{PROJECT}} INTERFACE cxx_std_23)

if({{PROJECT_UPPER}}_BUILD_TESTS)
    include({{PROJECT}}_testing)
    enable_testing()
    add_subdirectory(tests)
endif()

if({{PROJECT_UPPER}}_BUILD_EXAMPLES)
    add_subdirectory(examples)
endif()

if({{PROJECT_UPPER}}_INSTALL)
    install(TARGETS {{PROJECT}}
        EXPORT   {{PROJECT}}_targets
        FILE_SET {{PROJECT}}_headers DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
    )
    install(EXPORT {{PROJECT}}_targets
        FILE        {{PROJECT}}-targets.cmake
        NAMESPACE   {{PROJECT}}::
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/{{PROJECT}}
    )
    configure_package_config_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/cmake/{{PROJECT}}-config.cmake.in"
        "${CMAKE_CURRENT_BINARY_DIR}/{{PROJECT}}-config.cmake"
        INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/{{PROJECT}}
    )
    write_basic_package_version_file(
        "${CMAKE_CURRENT_BINARY_DIR}/{{PROJECT}}-config-version.cmake"
        VERSION ${PROJECT_VERSION} COMPATIBILITY SameMajorVersion
    )
    install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/{{PROJECT}}-config.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/{{PROJECT}}-config-version.cmake"
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/{{PROJECT}}
    )
endif()

message(STATUS "[{{PROJECT}}] v${PROJECT_VERSION} tests=${{{PROJECT_UPPER}}_BUILD_TESTS} "
               "examples=${{{PROJECT_UPPER}}_BUILD_EXAMPLES} "
               "werror=${{{PROJECT_UPPER}}_WARNINGS_AS_ERRORS}")
