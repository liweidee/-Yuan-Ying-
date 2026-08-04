cmake_minimum_required(VERSION 3.4.1)

project("yuanying")

# 关键：添加库搜索路径，指向官方示例中的 libnode/bin 目录
link_directories(${CMAKE_SOURCE_DIR}/../libnode/bin/${ANDROID_ABI})

add_library(
    native-lib
    SHARED
    native-lib.cpp
)

# 查找并链接 libnode.so
find_library(node-lib node)
target_link_libraries(
    native-lib
    ${node-lib}
    log
)