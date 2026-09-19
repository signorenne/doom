include_guard(GLOBAL)

#
# Provisions doctest so a fresh clone needs no manual setup. It comes from the
# upstream release tarball with a pinned hash, which keeps the download
# reproducible and independent of any system install. The TARGET guard skips
# the work when a parent project already provides doctest.
#
if(NOT TARGET doctest::doctest_with_main)
    set({{PROJECT_UPPER}}_DOCTEST_VERSION "2.4.12"
        CACHE STRING "doctest release to fetch")
    set({{PROJECT_UPPER}}_DOCTEST_SHA256
        "73381c7aa4dee704bd935609668cf41880ea7f19fa0504a200e13b74999c2d70"
        CACHE STRING "SHA256 of the doctest release tarball")

    message(STATUS "[{{PROJECT}}] fetching doctest ${{{PROJECT_UPPER}}_DOCTEST_VERSION}")
    include(FetchContent)
    # doctest declares cmake_minimum_required(VERSION 3.5); raise the policy
    # floor for its add_subdirectory so CMake 4 does not warn, then restore it.
    set(_prev_policy_min "${CMAKE_POLICY_VERSION_MINIMUM}")
    set(CMAKE_POLICY_VERSION_MINIMUM 3.10)
    FetchContent_Declare(
        doctest
        URL "https://github.com/doctest/doctest/archive/refs/tags/v${{{PROJECT_UPPER}}_DOCTEST_VERSION}.tar.gz"
        URL_HASH "SHA256=${{{PROJECT_UPPER}}_DOCTEST_SHA256}"
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    )
    FetchContent_MakeAvailable(doctest)
    set(CMAKE_POLICY_VERSION_MINIMUM "${_prev_policy_min}")

    # Re-expose doctest's headers as SYSTEM includes, so its own diagnostics
    # cannot break a warnings-as-errors build while ours stay strict.
    if(TARGET doctest)
        get_target_property(_doctest_inc doctest INTERFACE_INCLUDE_DIRECTORIES)
        if(_doctest_inc)
            set_target_properties(doctest PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "")
            target_include_directories(doctest SYSTEM INTERFACE ${_doctest_inc})
        endif()
    endif()
endif()
