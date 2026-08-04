cmake_minimum_required(VERSION 3.4.1)

project("yuanying")

# 添加库搜索路径，指向 app/libnode/bin 下对应架构的目录
# ${ANDROID_ABI} 在构建时会自动展开为 arm64-v8a, armeabi-v7a 等
link_directories(${CMAKE_SOURCE_DIR}/../libnode/bin/${ANDROID_ABI})

add_library(
    native-lib
    SHARED
    native-lib.cpp
)

# 查找 libnode.so
find_library(node-lib node)

target_link_libraries(
    native-lib
    ${node-lib}
    log
)