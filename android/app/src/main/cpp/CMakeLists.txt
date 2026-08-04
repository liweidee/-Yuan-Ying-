cmake_minimum_required(VERSION 3.4.1)
project("yuanying")

# 正确路径：从 src/main/cpp/ 往上三级到 app/，再进入 libnode/bin/${ANDROID_ABI}
set(NODE_SO_PATH ${CMAKE_SOURCE_DIR}/../../../libnode/bin/${ANDROID_ABI}/libnode.so)

add_library(node-lib SHARED IMPORTED)
set_target_properties(node-lib PROPERTIES
    IMPORTED_LOCATION ${NODE_SO_PATH}
)

add_library(
    native-lib
    SHARED
    native-lib.cpp
)

target_link_libraries(
    native-lib
    node-lib
    log
)