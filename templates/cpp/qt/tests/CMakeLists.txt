# The view model is testable because it depends on the repository, not on a
# window: these tests run headless.
find_package(Qt6 REQUIRED COMPONENTS Test)

qt_add_executable({{PROJECT}}_tests tst_mainviewmodel.cpp)

target_link_libraries({{PROJECT}}_tests
    PRIVATE
        {{PROJECT}}::core
        {{PROJECT}}::warnings
        Qt6::Test
)

add_test(NAME {{PROJECT}}_tests COMMAND {{PROJECT}}_tests)
set_tests_properties({{PROJECT}}_tests PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
)
