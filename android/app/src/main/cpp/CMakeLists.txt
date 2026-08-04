cmake_minimum_required(VERSION 3.4.1)
project("yuanying")

# 头文件路径（node.h 及所有依赖）
include_directories(${CMAKE_SOURCE_DIR}/../../../libnode/include/node/)

# libnode.so 路径：从 src/main/cpp/ 往上三级到 app/
set(NODE_SO_PATH ${CMAKE_SOURCE_DIR}/../../../libnode/bin/${ANDROID_ABI}/libnode.so)

# 以 IMPORTED 方式引入预编译的 libnode.so
add_library(node-lib SHARED IMPORTED)
set_target_properties(node-lib PROPERTIES
    IMPORTED_LOCATION ${NODE_SO_PATH}
)

# 编译自己的 native-lib
add_library(
    native-lib
    SHARED
    native-lib.cpp
)

# 链接
target_link_libraries(
    native-lib
    node-lib
    log
)