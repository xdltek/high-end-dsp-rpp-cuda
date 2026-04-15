cmake_minimum_required(VERSION 3.10)
project(rpp_fft_perf_boost_2d)

set(CMAKE_CXX_FLAGS "-g -fpermissive -Wall -lpthread -std=c++14 -Wno-error=deprecated-declarations -Wno-deprecated-declarations -Wno-unknown-pragmas ")

set(TEST_SOURCES rpp_fft_perf_boost_2d.cpp)
set(TEST_TARGET_NAME rpp_fft_perf_boost_2d)

if(platform STREQUAL "RPP_SIM_RT")
    set(RPP_TOOL_PATH /usr/local/rpp_sim/)
    set(RPP_TOOL_LIBS rpp_rt_iss urpp)
    add_definitions(-DRPP_SIM_RT)
else()
    set(RPP_TOOL_PATH /usr/local/rpp/)
    set(RPP_TOOL_LIBS urpp)
endif()

set(RPP_FFT_LIBS rppfft)

include_directories(${RPP_TOOL_PATH}/include/)
link_directories(${RPP_TOOL_PATH}/lib/)

add_executable(${TEST_TARGET_NAME} ${TEST_SOURCES})
target_link_libraries(${TEST_TARGET_NAME} ${RPP_TOOL_LIBS} ${RPP_FFT_LIBS})
