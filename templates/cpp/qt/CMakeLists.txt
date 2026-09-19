cmake_minimum_required(VERSION 3.25)

project({{PROJECT}}
    VERSION     0.1.0
    DESCRIPTION "{{PROJECT}}: a Qt Quick application"
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

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)

include(GNUInstallDirs)
include({{PROJECT}}_warnings)

# The model and the view models are a library, so the tests link the same code
# the application runs. main.cpp is only the composition root.
qt_add_library({{PROJECT}}_core STATIC
    src/model/Task.hpp
    src/model/TaskRepository.hpp
    src/model/TaskRepository.cpp
    src/viewmodel/TaskListModel.hpp
    src/viewmodel/TaskListModel.cpp
    src/viewmodel/MainViewModel.hpp
    src/viewmodel/MainViewModel.cpp
)
add_library({{PROJECT}}::core ALIAS {{PROJECT}}_core)

# src for the qualified includes we write, plus the two layer directories:
# the generated QML type registration includes each header by its bare name.
target_include_directories({{PROJECT}}_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/model
    ${CMAKE_CURRENT_SOURCE_DIR}/src/viewmodel
)
target_link_libraries({{PROJECT}}_core
    PUBLIC  Qt6::Core Qt6::Qml
    PRIVATE {{PROJECT}}::warnings
)

# A QML module is found by an import path holding a directory named after
# its URI. Left to itself the module lands at the top of the build
# directory, which no import path can name, so qmlls and qmllint cannot
# resolve the types the view models register and every use of one is an
# error in the editor. This puts it where the tools look.
set(QT_QML_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml)

# The view models carry QML_ELEMENT, so this module registers them under the
# URI {{PROJECT}} and no qmlRegisterType call is needed.
qt_add_qml_module({{PROJECT}}_core
    URI {{PROJECT}}
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/TaskListView.qml
)

qt_add_executable({{PROJECT}} src/main.cpp)
target_link_libraries({{PROJECT}}
    PRIVATE
        {{PROJECT}}::core
        {{PROJECT}}_coreplugin
        {{PROJECT}}::warnings
        Qt6::Gui
        Qt6::Quick
        Qt6::QuickControls2
)

set_target_properties({{PROJECT}} PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE    TRUE
)

if({{PROJECT_UPPER}}_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

install(TARGETS {{PROJECT}}
    BUNDLE  DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

message(STATUS "[{{PROJECT}}] v${PROJECT_VERSION} Qt ${Qt6_VERSION} "
               "tests=${{{PROJECT_UPPER}}_BUILD_TESTS} "
               "werror=${{{PROJECT_UPPER}}_WARNINGS_AS_ERRORS}")
