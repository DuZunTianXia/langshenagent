cmake_minimum_required(VERSION 3.14)
project(browser_bridge LANGUAGES CXX)

# langshenagent-browser-host.exe, the browsers' native messaging host (host.cpp).
# It goes beside langshenagent.exe with dev.langshenagent.browser.json, the manifest
# the browsers find it by: the installer's keys point there (see
# tool/langshenagent.iss), and its "path", relative, is the host beside it.
add_executable(langshenagent-browser-host "host.cpp")
apply_standard_settings(langshenagent-browser-host)
target_compile_options(langshenagent-browser-host PRIVATE /utf-8)
target_compile_definitions(langshenagent-browser-host PRIVATE
  "NOMINMAX" "WIN32_LEAN_AND_MEAN" "_WIN32_WINNT=0x0600")
target_link_libraries(langshenagent-browser-host PRIVATE "ws2_32.lib")
