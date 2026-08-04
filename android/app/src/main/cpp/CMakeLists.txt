cmake_minimum_required(VERSION 3.4.1)
project("yuanying")

# 正确指向 libnode.so 所在目录（往上两级到 app 目录）
set(NODE_LIB_DIR ${CMAKE_SOURCE_DIR}/../../libnode/bin/${ANDROID_ABI})

# 以 IMPORTED 方式声明 libnode.so
add_library(node-lib SHARED IMPORTED)
set_target_properties(node-lib PROPERTIES
    IMPORTED_LOCATION ${NODE_LIB_DIR}/libnode.so
)

# 编译自己的 native-lib
add_library(
    native-lib
    SHARED
    native-lib.cpp
)

# 链接库
target_link_libraries(
    native-lib
    node-lib
    log
)