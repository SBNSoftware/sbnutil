# ======================================================================
#  sbnutil main build file
#
#  cd .../path/to/build/directory
#  source .../path/to/lardataobj/ups/setup_for_development <-d|-p>
#  buildtool [-I /install/path] -bt[i] -jN
# ======================================================================

cmake_minimum_required(VERSION 3.20 FATAL_ERROR)

find_package(cetmodules REQUIRED)
project(sbnutil VERSION 01.00.00)

# Sbnutil has not architecture dependence
include(CetCMakeEnv)
cet_cmake_env( noarch )

# Scripts
add_subdirectory(scripts)

# packaging utility

cet_cmake_config()
