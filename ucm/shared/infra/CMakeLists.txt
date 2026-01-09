file(GLOB_RECURSE UCMINFRA_STATUS_SOURCE_FILES "status/*.*")
add_library(infra_status OBJECT ${UCMINFRA_STATUS_SOURCE_FILES})
target_include_directories(infra_status PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(infra_status PUBLIC fmt)

file(GLOB UCMINFRA_LOGGER_SOURCE_FILES "logger/*.*")
file(GLOB UCMINFRA_LOGGER_CC_FILES "logger/${LOGGER_BACKEND}/cc/*.cc")
add_library(infra_logger SHARED ${UCMINFRA_LOGGER_SOURCE_FILES} ${UCMINFRA_LOGGER_CC_FILES})
target_include_directories(infra_logger PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/logger
    ${CMAKE_CURRENT_SOURCE_DIR}/logger/${LOGGER_BACKEND}/cc
)
target_link_libraries(infra_logger PUBLIC fmt spdlog zlib)

file(GLOB UCMINFRA_LOGGER_CPY_FILES CONFIGURE_DEPENDS "logger/${LOGGER_BACKEND}/cpy/*.cc")
pybind11_add_module(ucmlogger ${UCMINFRA_LOGGER_CPY_FILES})
target_include_directories(ucmlogger PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/logger/${LOGGER_BACKEND}/cc
)
target_link_libraries(ucmlogger PRIVATE infra_logger pybind11::module)
# Override CMAKE_SKIP_RPATH for these targets to enable RPATH
# Set RPATH so ucmlogger can find libinfra_logger.so in the same directory
# $ORIGIN tells the dynamic linker to look in the same directory as the module
# Since CMAKE_SKIP_RPATH is set globally, we use linker flags directly

# Use -Wl,-rpath,$ORIGIN to set RPATH to same directory as the library
target_link_options(ucmlogger PRIVATE "-Wl,-rpath,\$ORIGIN")
target_link_options(infra_logger PRIVATE "-Wl,-rpath,\$ORIGIN")


file(RELATIVE_PATH UCMINFRA_INSTALL_REL_PATH
     ${CMAKE_SOURCE_DIR}
     ${CMAKE_CURRENT_SOURCE_DIR}
)
install(TARGETS ucmlogger infra_logger
        LIBRARY DESTINATION ${UCMINFRA_INSTALL_REL_PATH}
        COMPONENT ucm)

file(GLOB_RECURSE UCMINFRA_TEMPLATE_SOURCE_FILES "template/*.*")
add_library(infra_template OBJECT ${UCMINFRA_TEMPLATE_SOURCE_FILES})
target_include_directories(infra_template PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

file(GLOB_RECURSE UCMINFRA_THREAD_SOURCE_FILES "thread/*.*")
add_library(infra_thread OBJECT ${UCMINFRA_THREAD_SOURCE_FILES})
target_include_directories(infra_thread PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

file(GLOB_RECURSE UCMINFRA_TIME_SOURCE_FILES "time/*.*")
add_library(infra_time OBJECT ${UCMINFRA_TIME_SOURCE_FILES})
target_include_directories(infra_time PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
