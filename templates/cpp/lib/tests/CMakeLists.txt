# One binary per suite: a failing link or a crash stays contained, and a single
# suite can be run on its own while iterating.
add_executable({{PROJECT}}_tests
    test_counter.cpp
)

target_link_libraries({{PROJECT}}_tests
    PRIVATE
        {{PROJECT}}::{{PROJECT}}
        {{PROJECT}}::warnings
        doctest::doctest_with_main
)

add_test(NAME {{PROJECT}}_tests COMMAND {{PROJECT}}_tests)
