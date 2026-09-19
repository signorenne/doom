include_guard(GLOBAL)

#
# Build-only INTERFACE target collecting the compiler warnings.
# Link with: target_link_libraries(<target> PRIVATE {{PROJECT}}::warnings)
#
# Not exported. Tests and examples opt in; the header-only library never links
# it, because warnings apply to translation units, not to header-only deps.
#
add_library({{PROJECT}}_warnings INTERFACE)
add_library({{PROJECT}}::warnings ALIAS {{PROJECT}}_warnings)

if(MSVC)
    target_compile_options({{PROJECT}}_warnings INTERFACE
        /W4
        /permissive-
        /Zc:__cplusplus
        /Zc:preprocessor
    )
    if({{PROJECT_UPPER}}_WARNINGS_AS_ERRORS)
        target_compile_options({{PROJECT}}_warnings INTERFACE /WX)
    endif()
else()
    target_compile_options({{PROJECT}}_warnings INTERFACE
        -Wall
        -Wextra
        -Wpedantic
        -Wshadow
        -Wnon-virtual-dtor
        -Wold-style-cast
        -Wcast-align
        -Woverloaded-virtual
        -Wconversion
        -Wsign-conversion
        -Wnull-dereference
        -Wdouble-promotion
        -Wformat=2
        -Wimplicit-fallthrough
    )
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
        target_compile_options({{PROJECT}}_warnings INTERFACE
            -Wmisleading-indentation
            -Wduplicated-cond
            -Wduplicated-branches
            -Wlogical-op
            -Wuseless-cast
        )
    endif()
    if({{PROJECT_UPPER}}_WARNINGS_AS_ERRORS)
        target_compile_options({{PROJECT}}_warnings INTERFACE -Werror)
    endif()
endif()
