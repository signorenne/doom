# One runnable program per public component, so a reader can see the usage.
add_executable({{PROJECT}}_example_counter counter.cpp)

target_link_libraries({{PROJECT}}_example_counter
    PRIVATE
        {{PROJECT}}::{{PROJECT}}
        {{PROJECT}}::warnings
)
