add_executable({{PROJECT}}_tests
    test_options.cpp
)

target_link_libraries({{PROJECT}}_tests
    PRIVATE
        {{PROJECT}}::core
        {{PROJECT}}::warnings
        doctest::doctest_with_main
)

add_test(NAME {{PROJECT}}_tests COMMAND {{PROJECT}}_tests)
