cmake_minimum_required(VERSION 3.16)
project(OpenBurn VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(openburn main.cpp)

if(APPLE)
    enable_language(OBJCXX)
    add_executable(openburn-gui MACOSX_BUNDLE gui.mm)
    target_compile_options(openburn-gui PRIVATE -fobjc-arc)
    target_link_libraries(openburn-gui PRIVATE
        "-framework AppKit"
        "-framework UniformTypeIdentifiers"
    )
    set_target_properties(openburn-gui PROPERTIES
        MACOSX_BUNDLE_BUNDLE_NAME "OpenBurn"
        MACOSX_BUNDLE_GUI_IDENTIFIER "org.openburn.app"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    )
endif()
