cmake_minimum_required(VERSION 3.20)
project(KuroCat LANGUAGES CXX RC)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(KuroCat WIN32
    src/main.cpp
    app.rc
)
target_include_directories(KuroCat PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
set(DORAEMON_ART "${CMAKE_CURRENT_SOURCE_DIR}/../Resources/Doraemon")
set_property(SOURCE app.rc PROPERTY OBJECT_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/app.manifest"
    "${CMAKE_CURRENT_SOURCE_DIR}/resource.rc"
    "${DORAEMON_ART}/head.png"
    "${DORAEMON_ART}/body.png"
    "${DORAEMON_ART}/hand.png"
    "${DORAEMON_ART}/foot-right.png"
    "${DORAEMON_ART}/shoulder-mask.png"
)

target_compile_definitions(KuroCat PRIVATE UNICODE _UNICODE NOMINMAX _WIN32_WINNT=0x0601 WINVER=0x0601)
if(MSVC)
    target_compile_options(KuroCat PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:/O2;/utf-8;/EHsc;/W3;/MT>")
    target_link_options(KuroCat PRIVATE /SUBSYSTEM:WINDOWS,6.01 /MANIFEST:EMBED "/MANIFESTINPUT:${CMAKE_CURRENT_SOURCE_DIR}/app.manifest")
else()
    target_compile_definitions(KuroCat PRIVATE "$<$<COMPILE_LANGUAGE:RC>:KUROCAT_EMBED_MANIFEST>")
    target_compile_options(KuroCat PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:-O2>")
    target_link_options(KuroCat PRIVATE -municode -static -Wl,--major-subsystem-version,6,--minor-subsystem-version,1)
endif()

target_link_libraries(KuroCat PRIVATE user32 gdi32 gdiplus shell32 advapi32 wtsapi32 ole32)
