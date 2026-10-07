cmake_minimum_required (VERSION 3.0.2)
project (LibPHX)
if (NOT CMAKE_BUILD_TYPE)
  set (CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif ()
include (script/build/Shared.cmake)

# ------------------------------------------------------------------------------

file (GLOB HEADERS "include/*.h")
file (GLOB SOURCES "src/*.cpp")

add_library (phx SHARED ${SOURCES} ${HEADERS})
phx_configure_output_dir (phx)
phx_configure_target_properties (phx)

target_compile_definitions (phx PRIVATE LIBPHX_BUILDING=1)
target_include_directories (phx PUBLIC "include")
target_include_directories (phx PUBLIC "ext/include")
target_include_directories (phx PUBLIC "ext/include/bullet")
target_link_directories (phx PUBLIC "ext/lib/${PLATARCH}")

set_target_properties (phx PROPERTIES
  PREFIX "lib"
  OUTPUT_NAME_DEBUG "phx${ARCH}d"
  OUTPUT_NAME_RELEASE "phx${ARCH}r"
  OUTPUT_NAME_RELWITHDEBINFO "phx${ARCH}"
  OUTPUT_NAME_MINSIZEREL "phx${ARCH}rm")

# ------------------------------------------------------------------------------

if (WINDOWS)

  # register an external shared library
  function (add_extlib name lib dll)
    add_library (${name} SHARED IMPORTED GLOBAL)
    set_property (TARGET ${name} PROPERTY IMPORTED_IMPLIB "${CMAKE_CURRENT_SOURCE_DIR}/ext/lib/${PLATARCH}/${lib}")
    set_property (TARGET ${name} PROPERTY IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/ext/lib/${PLATARCH}/${dll}")
  endfunction ()

  # link target to an external library; also add a post-build step to
  # copy the library DLL into the bin folder
  function (target_link_extlib target lib)
    target_link_libraries (${target} ${lib})
    add_custom_command (TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_if_different
      $<TARGET_FILE:${lib}> $<TARGET_FILE_DIR:${target}>
    )
  endfunction ()

  add_extlib (glew glew32.lib glew32.dll)
  add_extlib (lz4 liblz4.lib liblz4.dll)
  add_extlib (lua51 lua51.lib lua51.dll)
  add_extlib (sdl2 SDL2.lib SDL2.dll)

  if (ARCH EQUAL "32")
    add_extlib (fmod fmodL_vc.lib fmodL.dll)
    add_extlib (fmodstudio fmodstudioL_vc.lib fmodstudioL.dll)
  else ()
    add_extlib (fmod fmodL64_vc.lib fmodL64.dll)
    add_extlib (fmodstudio fmodstudioL64_vc.lib fmodstudioL64.dll)
  endif ()

elseif (LINUX)

  # Prefer vendored linux64 shared libs (Bullet / FMOD / lz4). System packages
  # supply GL / GLEW / SDL2 / FreeType / LuaJIT.
  set (PHX_LINUX_LIBDIR "${CMAKE_CURRENT_SOURCE_DIR}/ext/lib/${PLATARCH}")

  # SONAME helpers for vendored .so.2.87 / fmod.so.10 artifacts
  if (EXISTS "${PHX_LINUX_LIBDIR}/libBulletCollision.so.2.87" AND NOT EXISTS "${PHX_LINUX_LIBDIR}/libBulletCollision.so")
    file (CREATE_LINK "libBulletCollision.so.2.87" "${PHX_LINUX_LIBDIR}/libBulletCollision.so" SYMBOLIC)
  endif ()
  if (EXISTS "${PHX_LINUX_LIBDIR}/libBulletDynamics.so.2.87" AND NOT EXISTS "${PHX_LINUX_LIBDIR}/libBulletDynamics.so")
    file (CREATE_LINK "libBulletDynamics.so.2.87" "${PHX_LINUX_LIBDIR}/libBulletDynamics.so" SYMBOLIC)
  endif ()
  if (EXISTS "${PHX_LINUX_LIBDIR}/libLinearMath.so.2.87" AND NOT EXISTS "${PHX_LINUX_LIBDIR}/libLinearMath.so")
    file (CREATE_LINK "libLinearMath.so.2.87" "${PHX_LINUX_LIBDIR}/libLinearMath.so" SYMBOLIC)
  endif ()
  if (EXISTS "${PHX_LINUX_LIBDIR}/libfmod.so" AND NOT EXISTS "${PHX_LINUX_LIBDIR}/libfmod.so.10")
    file (CREATE_LINK "libfmod.so" "${PHX_LINUX_LIBDIR}/libfmod.so.10" SYMBOLIC)
  endif ()
  if (EXISTS "${PHX_LINUX_LIBDIR}/libfmodstudio.so" AND NOT EXISTS "${PHX_LINUX_LIBDIR}/libfmodstudio.so.10")
    file (CREATE_LINK "libfmodstudio.so" "${PHX_LINUX_LIBDIR}/libfmodstudio.so.10" SYMBOLIC)
  endif ()
  if (EXISTS "${PHX_LINUX_LIBDIR}/libfmodL.so" AND NOT EXISTS "${PHX_LINUX_LIBDIR}/libfmodL.so.10")
    file (CREATE_LINK "libfmodL.so" "${PHX_LINUX_LIBDIR}/libfmodL.so.10" SYMBOLIC)
  endif ()
  if (EXISTS "${PHX_LINUX_LIBDIR}/libfmodstudioL.so" AND NOT EXISTS "${PHX_LINUX_LIBDIR}/libfmodstudioL.so.10")
    file (CREATE_LINK "libfmodstudioL.so" "${PHX_LINUX_LIBDIR}/libfmodstudioL.so.10" SYMBOLIC)
  endif ()

endif ()

# ------------------------------------------------------------------------------

if (WINDOWS)

  target_link_libraries (phx
    opengl32.lib
    user32.lib winmm.lib Ws2_32.lib
    freetype.lib
    BulletCollision.lib BulletDynamics.lib LinearMath.lib)

  target_link_extlib (phx glew)
  target_link_extlib (phx sdl2)
  target_link_extlib (phx lz4)
  target_link_extlib (phx lua51)
  target_link_extlib (phx fmod)
  target_link_extlib (phx fmodstudio)

elseif (LINUX)

  target_link_libraries (phx
    GL
    GLEW
    dl
    pthread
    SDL2
    freetype
    luajit-5.1
    lz4
    fmod
    fmodstudio
    BulletCollision
    BulletDynamics
    LinearMath)

  # Runtime search: bin/ first (copied libs), then vendored ext path
  target_link_options (phx PRIVATE
    "-Wl,-rpath,$ORIGIN"
    "-Wl,-rpath,${CMAKE_CURRENT_SOURCE_DIR}/ext/lib/${PLATARCH}")

  # Ensure the linker finds vendored linux64 libs at link time
  target_link_directories (phx PUBLIC "ext/lib/${PLATARCH}")

endif ()
