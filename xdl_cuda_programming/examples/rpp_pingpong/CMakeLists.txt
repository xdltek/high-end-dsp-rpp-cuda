cmake_minimum_required(VERSION 3.10)
project(rpp_pingpong)

set(CMAKE_C_COMPILER_FORCED TRUE)
set(CMAKE_CXX_COMPILER_FORCED TRUE)
set(CMAKE_CUDA_COMPILER_FORCED TRUE)
set(CMAKE_CUDA_COMPILER_ID_RUN 1)

set(CMAKE_CUDA_COMPILER /usr/local/bin/clang++)
set(CMAKE_CUDA_ARCHITECTURES RPP)
set(_CMAKE_CUDA_WHOLE_FLAG "-c")
enable_language(CUDA)
set(CMAKE_CUDA_LINK_EXECUTABLE "${CMAKE_CUDA_COMPILER} ${CMAKE_CUDA_LINK_EXECUTABLE}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -std=c++17 -O3 -Wno-write-strings")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-rpath -Wl,$ORIGIN")
set(CMAKE_CUDA_FLAGS "-fPIC -fno-unroll-loops -O3 -ffp-contract=off -nocudalib -nocudainc -save-temps -std=c++14")

if(platform STREQUAL "RPP_SIM_RT")
    set(RPP_TOOL_PATH /usr/local/rpp_sim/)
    set(RPP_TOOL_LIBS rpp_rt_iss urpp)
    add_definitions(-DRPP_SIM_RT)
else()
    set(RPP_TOOL_PATH /usr/local/rpp/)
    set(RPP_TOOL_LIBS urpp)
endif()

include_directories(${RPP_TOOL_PATH}/include)
link_directories(${RPP_TOOL_PATH}/lib)

set(TEST_SOURCES rpp_pingpong.cu)
set(TEST_TARGET_NAME rpp_pingpong)

add_executable(${TEST_TARGET_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/${TEST_SOURCES})
target_link_libraries(${TEST_TARGET_NAME} ${RPP_TOOL_LIBS})

add_definitions(-w)
