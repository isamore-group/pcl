include(${PROJECT_SOURCE_DIR}/cmake/pcl_utils.cmake)

# Store location of current dir, because value of CMAKE_CURRENT_LIST_DIR is
# set to the directory where a function is used, not where a function is defined
set(_PCL_TARGET_CMAKE_DIR ${CMAKE_CURRENT_LIST_DIR})

# Instrumentation settings - following liquid-dsp pattern
set(PASS_PATH "$ENV{PASS_PATH}")
set(LLVM_DIR "$ENV{LLVM_DIR}")

if (PASS_PATH AND LLVM_DIR)
    message(STATUS "PCL Instrumentation enabled - PASS_PATH: ${PASS_PATH}")
    set(LLVM_LINK "${LLVM_DIR}/bin/llvm-link")
    message(STATUS "LLVM_LINK: ${LLVM_LINK}")  
    set(OPT "${LLVM_DIR}/bin/opt")
    message(STATUS "OPT: ${OPT}")
    set(CLANG "${LLVM_DIR}/bin/clang")
    message(STATUS "CLANG: ${CLANG}")

    # Set compilers for instrumentation
    set(CMAKE_C_COMPILER ${CLANG})
    set(CMAKE_CXX_COMPILER ${CLANG}++)
    set(PCL_INSTRUMENTATION_ENABLED TRUE)
else()
    message(STATUS "PCL Instrumentation disabled - PASS_PATH or LLVM_DIR not set")
    set(PCL_INSTRUMENTATION_ENABLED FALSE)
endif()

###############################################################################
# Add an option to build a subsystem or not.
# _var The name of the variable to store the option in.
# _name The name of the option's target subsystem.
# _desc The description of the subsystem.
# _default The default value (TRUE or FALSE)
# ARGV5 The reason for disabling if the default is FALSE.
macro(PCL_SUBSYS_OPTION _var _name _desc _default)
  set(_opt_name "BUILD_${_name}")
  PCL_GET_SUBSYS_HYPERSTATUS(subsys_status ${_name})
  if(NOT ("${subsys_status}" STREQUAL "AUTO_OFF"))
    option(${_opt_name} ${_desc} ${_default})
    if((NOT ${_default} AND NOT ${_opt_name}) OR ("${_default}" STREQUAL "AUTO_OFF"))
      set(${_var} FALSE)
      if(${ARGC} GREATER 4)
        set(_reason ${ARGV4})
      else()
        set(_reason "Disabled by default.")
      endif()
      PCL_SET_SUBSYS_STATUS(${_name} FALSE ${_reason})
      PCL_DISABLE_DEPENDIES(${_name})
    elseif(NOT ${_opt_name})
      set(${_var} FALSE)
      PCL_SET_SUBSYS_STATUS(${_name} FALSE "Disabled manually.")
      PCL_DISABLE_DEPENDIES(${_name})
    else()
      set(${_var} TRUE)
      PCL_SET_SUBSYS_STATUS(${_name} TRUE)
      PCL_ENABLE_DEPENDIES(${_name})
    endif()
  endif()
  PCL_ADD_SUBSYSTEM(${_name} ${_desc})
endmacro()

###############################################################################
# Add an option to build a subsystem or not.
# _var The name of the variable to store the option in.
# _parent The name of the parent subsystem
# _name The name of the option's target subsubsystem.
# _desc The description of the subsubsystem.
# _default The default value (TRUE or FALSE)
# ARGV5 The reason for disabling if the default is FALSE.
macro(PCL_SUBSUBSYS_OPTION _var _parent _name _desc _default)
  set(_opt_name "BUILD_${_parent}_${_name}")
  PCL_GET_SUBSYS_HYPERSTATUS(parent_status ${_parent})
  if(NOT ("${parent_status}" STREQUAL "AUTO_OFF") AND NOT ("${parent_status}" STREQUAL "OFF"))
    PCL_GET_SUBSYS_HYPERSTATUS(subsys_status ${_parent}_${_name})
    if(NOT ("${subsys_status}" STREQUAL "AUTO_OFF"))
      option(${_opt_name} ${_desc} ${_default})
      if((NOT ${_default} AND NOT ${_opt_name}) OR ("${_default}" STREQUAL "AUTO_OFF"))
        set(${_var} FALSE)
        if(${ARGC} GREATER 5)
          set(_reason ${ARGV5})
        else()
          set(_reason "Disabled by default.")
        endif()
        PCL_SET_SUBSYS_STATUS(${_parent}_${_name} FALSE ${_reason})
        PCL_DISABLE_DEPENDIES(${_parent}_${_name})
      elseif(NOT ${_opt_name})
        set(${_var} FALSE)
        PCL_SET_SUBSYS_STATUS(${_parent}_${_name} FALSE "Disabled manually.")
        PCL_DISABLE_DEPENDIES(${_parent}_${_name})
      else()
        set(${_var} TRUE)
        PCL_SET_SUBSYS_STATUS(${_parent}_${_name} TRUE)
        PCL_ENABLE_DEPENDIES(${_parent}_${_name})
      endif()
    endif()
  endif()
  PCL_ADD_SUBSUBSYSTEM(${_parent} ${_name} ${_desc})
endmacro()

###############################################################################
# Make one subsystem depend on one or more other subsystems, and disable it if
# they are not being built.
# _var The cumulative build variable. This will be set to FALSE if the
#   dependencies are not met.
# ARGN The subsystems and external libraries to depend on.
macro(PCL_SUBSYS_DEPEND _var)
  set(options)
  set(oneValueArgs)
  set(multiValueArgs DEPS EXT_DEPS OPT_DEPS NAME PARENT_NAME)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_SUBSYS_DEPEND: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT ARGS_NAME)
    message(FATAL_ERROR "PCL_SUBSYS_DEPEND requires parameter NAME!")
  endif()

  set(_name ${ARGS_NAME})
  if(ARGS_PARENT_NAME)
    string(PREPEND _name "${ARGS_PARENT_NAME}_")
  endif()

  if(ARGS_DEPS)
    SET_IN_GLOBAL_MAP(PCL_SUBSYS_DEPS ${_name} "${ARGS_DEPS}")
  endif()
  if(ARGS_EXT_DEPS)
    SET_IN_GLOBAL_MAP(PCL_SUBSYS_EXT_DEPS ${_name} "${ARGS_EXT_DEPS}")
  endif()
  if(ARGS_OPT_DEPS)
    SET_IN_GLOBAL_MAP(PCL_SUBSYS_OPT_DEPS ${_name} "${ARGS_OPT_DEPS}")
  endif()
  GET_IN_MAP(subsys_status PCL_SUBSYS_HYPERSTATUS ${_name})
  if(${_var} AND (NOT ("${subsys_status}" STREQUAL "AUTO_OFF")))
    if(ARGS_DEPS)
      foreach(_dep ${ARGS_DEPS})
        PCL_GET_SUBSYS_STATUS(_status ${_dep})
        if(NOT _status)
          set(${_var} FALSE)
          PCL_SET_SUBSYS_STATUS(${_name} FALSE "Requires ${_dep}.")
        endif()
      endforeach()
    endif()
    if(ARGS_EXT_DEPS)
      foreach(_dep ${ARGS_EXT_DEPS})
        string(TOUPPER "${_dep}_found" EXT_DEP_FOUND)
        #Variable EXT_DEP_FOUND expands to ie. QHULL_FOUND which in turn is then used to see if the EXT_DEPS is found.
        if(NOT ${EXT_DEP_FOUND})
          set(${_var} FALSE)
          PCL_SET_SUBSYS_STATUS(${_name} FALSE "Requires external library ${_dep}.")
        endif()
      endforeach()
    endif()
  endif()
endmacro()

###############################################################################
# Adds version information to executable/library in form of a version.rc. This works only with MSVC.
#
# _name The library name.
##
function(PCL_ADD_VERSION_INFO _name)
  if(MSVC)
    string(REPLACE "." "," VERSION_INFO_VERSION_WITH_COMMA ${PCL_VERSION})
    if (SUBSUBSYS_DESC)
      set(VERSION_INFO_DISPLAY_NAME ${SUBSUBSYS_DESC})
    else()
      set(VERSION_INFO_DISPLAY_NAME ${SUBSYS_DESC})
    endif()
    set(VERSION_INFO_ICON_PATH "${_PCL_TARGET_CMAKE_DIR}/images/pcl.ico")
    configure_file(${_PCL_TARGET_CMAKE_DIR}/version.rc.in ${PROJECT_BINARY_DIR}/${_name}_version.rc @ONLY)
    target_sources(${_name} PRIVATE ${PROJECT_BINARY_DIR}/${_name}_version.rc)
  endif()
endfunction()

###############################################################################
# Add a set of include files to install.
# _component The part of PCL that the install files belong to.
# _subdir The sub-directory for these include files.
# ARGN The include files.
macro(PCL_ADD_INCLUDES _component _subdir)
  install(FILES ${ARGN}
          DESTINATION ${INCLUDE_INSTALL_DIR}/${_subdir}
          COMPONENT pcl_${_component})
endmacro()

###############################################################################
# Add a library target.
# _name The library name.
# COMPONENT The part of PCL that this library belongs to.
# SOURCES The source files for the library.
function(PCL_ADD_LIBRARY _name)
  set(options)
  set(oneValueArgs COMPONENT)
  set(multiValueArgs SOURCES INCLUDES)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_ADD_LIBRARY: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT ARGS_COMPONENT)
    message(FATAL_ERROR "PCL_ADD_LIBRARY requires parameter COMPONENT.")
  endif()

  if(NOT ARGS_SOURCES)
    if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.19)
      add_library(${_name} INTERFACE ${ARGS_INCLUDES})
      set_target_properties(${_name} PROPERTIES FOLDER "Libraries")
    else()
      add_library(${_name} INTERFACE)
    endif()
    
    target_include_directories(${_name} INTERFACE
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
      $<INSTALL_INTERFACE:${INCLUDE_INSTALL_ROOT}> 
    )
  else()
    if(PCL_INSTRUMENTATION_ENABLED)
      # Filter out non-.cpp/.c files for instrumentation
      set(CPP_SOURCES)
      foreach(src ${ARGS_SOURCES})
        get_filename_component(ext ${src} EXT)
        if(ext STREQUAL ".cpp" OR ext STREQUAL ".c")
          list(APPEND CPP_SOURCES ${src})
        endif()
      endforeach()

      if(CPP_SOURCES)
        add_library(${_name} ${PCL_LIB_TYPE} ${ARGS_SOURCES})
        PCL_ADD_VERSION_INFO(${_name})
        target_compile_features(${_name} PUBLIC ${PCL_CXX_COMPILE_FEATURES})

        target_include_directories(${_name} PUBLIC
          $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
          $<INSTALL_INTERFACE:${INCLUDE_INSTALL_ROOT}> 
        )

        target_link_libraries(${_name} Threads::Threads)
        if(TARGET OpenMP::OpenMP_CXX)
          target_link_libraries(${_name} OpenMP::OpenMP_CXX)
        endif()

        if((UNIX AND NOT ANDROID) OR MINGW)
          target_link_libraries(${_name} m ${ATOMIC_LIBRARY})
        endif()

        if(MINGW)
          target_link_libraries(${_name} gomp)
        endif()

        if(MSVC)
          target_link_libraries(${_name} delayimp.lib)
        endif()
        
        set_target_properties(${_name} PROPERTIES
          VERSION ${PCL_VERSION}
          SOVERSION ${PCL_VERSION_MAJOR}.${PCL_VERSION_MINOR}
          DEFINE_SYMBOL "PCLAPI_EXPORTS"
          FOLDER "Libraries")

        # Now create the instrumentation workflow
        set(PCL_LL_FILES)
        set(PCL_LL_INSTRUMENTED_FILES)
        
        foreach(cpp_source ${CPP_SOURCES})
          # Create unique file names by using full relative path
          string(REPLACE "/" "_" source_path_safe ${cpp_source})
          get_filename_component(source_name ${source_path_safe} NAME_WE)
          set(ll_file "${CMAKE_CURRENT_BINARY_DIR}/${_name}_${source_name}.ll")
          set(ll_instrumented_file "${CMAKE_CURRENT_BINARY_DIR}/${_name}_${source_name}_instrumented.ll")
          
          # Compile to LLVM IR
          get_filename_component(source_ext ${cpp_source} EXT)
          if(source_ext STREQUAL ".c")
            set(LANG_FLAGS "-std=c11")
          else()
            set(LANG_FLAGS "-std=c++17")
          endif()
          
          add_custom_command(
            OUTPUT ${ll_file}
            COMMAND ${CLANG} -S -emit-llvm ${LANG_FLAGS} -fPIC -O2 
                    -fno-vectorize -fno-slp-vectorize -ffp-contract=off -mno-avx -mno-avx2 -mno-avx512f -mno-fma
                    -I${CMAKE_CURRENT_SOURCE_DIR}/include 
                    -I${PROJECT_SOURCE_DIR}/common/include
                    -I${PROJECT_SOURCE_DIR}/kdtree/include
                    -I${PROJECT_SOURCE_DIR}/octree/include
                    -I${PROJECT_SOURCE_DIR}/search/include
                    -I${PROJECT_SOURCE_DIR}/sample_consensus/include
                    -I${PROJECT_SOURCE_DIR}/filters/include
                    -I${PROJECT_SOURCE_DIR}/2d/include
                    -I${PROJECT_SOURCE_DIR}/geometry/include
                    -I${PROJECT_SOURCE_DIR}/io/include
                    -I${PROJECT_SOURCE_DIR}/features/include
                    -I${PROJECT_SOURCE_DIR}/ml/include
                    -I${PROJECT_SOURCE_DIR}/segmentation/include
                    -I${PROJECT_SOURCE_DIR}/surface/include
                    -I${PROJECT_SOURCE_DIR}/registration/include
                    -I${PROJECT_SOURCE_DIR}/keypoints/include
                    -I${PROJECT_SOURCE_DIR}/tracking/include
                    -I${PROJECT_SOURCE_DIR}/recognition/include
                    -I${PROJECT_SOURCE_DIR}/stereo/include
                    -I${PROJECT_SOURCE_DIR}/outofcore/include
                    -I${CMAKE_CURRENT_BINARY_DIR}/include
                    -I${PROJECT_BINARY_DIR}/include
                    -I${FLANN_INSTALL_PATH}/include
                    -I${EIGEN3_INCLUDE_DIR}
                    -I/home/uvxiao/.local/include
                    -c ${CMAKE_CURRENT_SOURCE_DIR}/${cpp_source} -o ${ll_file}
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${cpp_source}
          )
          
          # Instrument LLVM IR with fast counting  
          add_custom_command(
            OUTPUT ${ll_instrumented_file}
            COMMAND ${OPT} -load-pass-plugin="${PASS_PATH}" -passes=bb_instrument -just-count ${ll_file} -o ${ll_instrumented_file} > /dev/null 2>&1
            DEPENDS ${ll_file}
          )
          
          list(APPEND PCL_LL_FILES ${ll_file})
          list(APPEND PCL_LL_INSTRUMENTED_FILES ${ll_instrumented_file})
        endforeach()

        # Step 2: Link LLVM IR files into bitcode and generate linked .ll file
        add_custom_command(
          OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${_name}.bc
          COMMAND ${LLVM_LINK} ${PCL_LL_FILES} -o ${CMAKE_CURRENT_BINARY_DIR}/${_name}.bc
          DEPENDS ${PCL_LL_FILES}
        )

        # Generate linked .ll file (human-readable LLVM IR) for the module
        add_custom_command(
          OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${_name}.ll
          COMMAND ${LLVM_LINK} ${PCL_LL_FILES} -S -o ${CMAKE_CURRENT_BINARY_DIR}/${_name}.ll
          DEPENDS ${PCL_LL_FILES}
        )

        # Generate operation count CSV file using bb_instrument pass with just-count and count-file options
        add_custom_command(
          OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${_name}_op_count.csv
          COMMAND ${OPT} -load-pass-plugin="${PASS_PATH}" -passes=bb_instrument -just-count ${CMAKE_CURRENT_BINARY_DIR}/${_name}.bc -o /dev/null --count-file=${CMAKE_CURRENT_BINARY_DIR}/${_name}_op_count.csv > /dev/null 2>&1
          DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${_name}.bc
        )

        add_custom_command(
          OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented.bc
          COMMAND ${LLVM_LINK} ${PCL_LL_INSTRUMENTED_FILES} -o ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented.bc
          DEPENDS ${PCL_LL_INSTRUMENTED_FILES}
        )

        # Step 3: Create instrumented shared library and overwrite the dummy one
        add_custom_command(
          OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented_lib.stamp
          COMMAND ${CLANG} -shared -fPIC -fno-vectorize -fno-slp-vectorize -ffp-contract=off -mno-avx -mno-avx2 -mno-avx512f -mno-fma
                  ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented.bc 
                  -o $<TARGET_FILE:${_name}> -L/home/uvxiao/.local/lib -llz4
          COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented_lib.stamp
          DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented.bc
        )

        # Create custom targets for instrumented artifacts
        add_custom_target(${_name}_ll ALL DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${_name}.bc ${CMAKE_CURRENT_BINARY_DIR}/${_name}.ll)
        add_custom_target(${_name}_ll_instrumented ALL DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented.bc)
        add_custom_target(${_name}_op_count ALL DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${_name}_op_count.csv)
        add_custom_target(${_name}_instrumented_lib ALL DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented_lib.stamp)
        
        # Add stamp file to clean target
        set_property(TARGET ${_name}_instrumented_lib PROPERTY ADDITIONAL_CLEAN_FILES 
          "${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented_lib.stamp")
        
        # Make sure the instrumented library is built after the dummy library
        add_dependencies(${_name}_instrumented_lib ${_name})
        
        # Add to global list for all_instrumented_libs target
        set_property(GLOBAL APPEND PROPERTY PCL_INSTRUMENTED_LIBS ${_name}_instrumented_lib)
        # Also add the linked .ll and op_count.csv targets
        set_property(GLOBAL APPEND PROPERTY PCL_INSTRUMENTED_LIBS ${_name}_ll)
        set_property(GLOBAL APPEND PROPERTY PCL_INSTRUMENTED_LIBS ${_name}_op_count)

        install(TARGETS ${_name}
                RUNTIME DESTINATION ${BIN_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT}
                LIBRARY DESTINATION ${LIB_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT}
                ARCHIVE DESTINATION ${LIB_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT})
        
        # Install the bitcode files, linked LLVM IR, and operation count CSV
        install(FILES 
          ${CMAKE_CURRENT_BINARY_DIR}/${_name}.bc
          ${CMAKE_CURRENT_BINARY_DIR}/${_name}.ll
          ${CMAKE_CURRENT_BINARY_DIR}/${_name}_instrumented.bc
          ${CMAKE_CURRENT_BINARY_DIR}/${_name}_op_count.csv
          DESTINATION ${LIB_INSTALL_DIR}
          COMPONENT pcl_${ARGS_COMPONENT}
        )
      else()
        # No .cpp/.c files to instrument, create regular library
        add_library(${_name} ${PCL_LIB_TYPE} ${ARGS_SOURCES})
        PCL_ADD_VERSION_INFO(${_name})
        target_compile_features(${_name} PUBLIC ${PCL_CXX_COMPILE_FEATURES})

        target_include_directories(${_name} PUBLIC
          $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
          $<INSTALL_INTERFACE:${INCLUDE_INSTALL_ROOT}> 
        )

        target_link_libraries(${_name} Threads::Threads)
        if(TARGET OpenMP::OpenMP_CXX)
          target_link_libraries(${_name} OpenMP::OpenMP_CXX)
        endif()

        if((UNIX AND NOT ANDROID) OR MINGW)
          target_link_libraries(${_name} m ${ATOMIC_LIBRARY})
        endif()

        if(MINGW)
          target_link_libraries(${_name} gomp)
        endif()

        if(MSVC)
          target_link_libraries(${_name} delayimp.lib)
        endif()
        
        set_target_properties(${_name} PROPERTIES
          VERSION ${PCL_VERSION}
          SOVERSION ${PCL_VERSION_MAJOR}.${PCL_VERSION_MINOR}
          DEFINE_SYMBOL "PCLAPI_EXPORTS"
          FOLDER "Libraries")

        install(TARGETS ${_name}
                RUNTIME DESTINATION ${BIN_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT}
                LIBRARY DESTINATION ${LIB_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT}
                ARCHIVE DESTINATION ${LIB_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT})
      endif()
    else()
      # Non-instrumented build - create regular library
      add_library(${_name} ${PCL_LIB_TYPE} ${ARGS_SOURCES})
      PCL_ADD_VERSION_INFO(${_name})
      target_compile_features(${_name} PUBLIC ${PCL_CXX_COMPILE_FEATURES})

      target_include_directories(${_name} PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${INCLUDE_INSTALL_ROOT}> 
      )

      target_link_libraries(${_name} Threads::Threads)
      if(TARGET OpenMP::OpenMP_CXX)
        target_link_libraries(${_name} OpenMP::OpenMP_CXX)
      endif()

      if((UNIX AND NOT ANDROID) OR MINGW)
        target_link_libraries(${_name} m ${ATOMIC_LIBRARY})
      endif()

      if(MINGW)
        target_link_libraries(${_name} gomp)
      endif()

      if(MSVC)
        target_link_libraries(${_name} delayimp.lib)
      endif()
      
      set_target_properties(${_name} PROPERTIES
        VERSION ${PCL_VERSION}
        SOVERSION ${PCL_VERSION_MAJOR}.${PCL_VERSION_MINOR}
        DEFINE_SYMBOL "PCLAPI_EXPORTS"
        FOLDER "Libraries")

      install(TARGETS ${_name}
              RUNTIME DESTINATION ${BIN_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT}
              LIBRARY DESTINATION ${LIB_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT}
              ARCHIVE DESTINATION ${LIB_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT})

      # Copy PDB if available
      if(MSVC AND ${PCL_LIB_TYPE} EQUAL "SHARED")
        install(FILES $<TARGET_PDB_FILE:${_name}> DESTINATION ${BIN_INSTALL_DIR} OPTIONAL)
      endif()
    endif()
  endif()
endfunction()

###############################################################################
# Add a cuda library target.
# _name The library name.
# COMPONENT The part of PCL that this library belongs to.
# SOURCES The source files for the library.
function(PCL_CUDA_ADD_LIBRARY _name)
  set(options)
  set(oneValueArgs COMPONENT)
  set(multiValueArgs SOURCES)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_CUDA_ADD_LIBRARY: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT ARGS_COMPONENT)
    message(FATAL_ERROR "PCL_CUDA_ADD_LIBRARY requires parameter COMPONENT.")
  endif()

  REMOVE_VTK_DEFINITIONS()
  if(NOT ARGS_SOURCES)
    add_library(${_name} INTERFACE)
    
    target_include_directories(${_name} INTERFACE
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${INCLUDE_INSTALL_ROOT}> 
    )

  else()
    add_library(${_name} ${PCL_LIB_TYPE} ${ARGS_SOURCES})
  
    PCL_ADD_VERSION_INFO(${_name})
  
    target_compile_options(${_name} PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: ${GEN_CODE} --expt-relaxed-constexpr>)
  
    target_include_directories(${_name} PUBLIC
      $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
      $<INSTALL_INTERFACE:${INCLUDE_INSTALL_ROOT}> 
    )
  
    target_include_directories(${_name} PRIVATE ${CUDA_TOOLKIT_INCLUDE})
  
    if(MSVC)
      target_link_libraries(${_name} delayimp.lib)  # because delay load is enabled for openmp.dll
    endif()
  
    set_target_properties(${_name} PROPERTIES
      VERSION ${PCL_VERSION}
      SOVERSION ${PCL_VERSION_MAJOR}.${PCL_VERSION_MINOR}
      DEFINE_SYMBOL "PCLAPI_EXPORTS")
    set_target_properties(${_name} PROPERTIES FOLDER "Libraries")
  endif()

  install(TARGETS ${_name}
          RUNTIME DESTINATION ${BIN_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT}
          LIBRARY DESTINATION ${LIB_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT}
          ARCHIVE DESTINATION ${LIB_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT})
endfunction()

###############################################################################
# Add an executable target.
# _name The executable name.
# BUNDLE Target should be handled as bundle (APPLE and VTK_USE_COCOA only)
# COMPONENT The part of PCL that this library belongs to.
# SOURCES The source files for the library.
function(PCL_ADD_EXECUTABLE _name)
  set(options BUNDLE)
  set(oneValueArgs COMPONENT)
  set(multiValueArgs SOURCES)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_ADD_EXECUTABLE: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT ARGS_COMPONENT)
    message(FATAL_ERROR "PCL_ADD_EXECUTABLE requires parameter COMPONENT.")
  endif()

  if(ARGS_BUNDLE AND APPLE AND VTK_USE_COCOA)
    add_executable(${_name} MACOSX_BUNDLE ${ARGS_SOURCES})
  else()
    add_executable(${_name} ${ARGS_SOURCES})
  endif()
  PCL_ADD_VERSION_INFO(${_name})

  target_link_libraries(${_name} Threads::Threads)

  if(WIN32 AND MSVC)
    set_target_properties(${_name} PROPERTIES DEBUG_OUTPUT_NAME ${_name}${CMAKE_DEBUG_POSTFIX}
                                              RELEASE_OUTPUT_NAME ${_name}${CMAKE_RELEASE_POSTFIX})
  endif()

  # Some app targets report are defined with subsys other than apps
  # It's simpler check for tools and assume everything else as an app
  if(${ARGS_COMPONENT} STREQUAL "tools")
    set_target_properties(${_name} PROPERTIES FOLDER "Tools")
  else()
    set_target_properties(${_name} PROPERTIES FOLDER "Apps")
  endif()

  set(PCL_EXECUTABLES ${PCL_EXECUTABLES} ${_name})

  if(ARGS_BUNDLE AND APPLE AND VTK_USE_COCOA)
    install(TARGETS ${_name} BUNDLE DESTINATION ${BIN_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT})
  else()
    install(TARGETS ${_name} RUNTIME DESTINATION ${BIN_INSTALL_DIR} COMPONENT pcl_${ARGS_COMPONENT})
  endif()

  string(TOUPPER ${ARGS_COMPONENT} _component_upper)
  set(PCL_${_component_upper}_ALL_TARGETS ${PCL_${_component_upper}_ALL_TARGETS} ${_name} PARENT_SCOPE)
endfunction()

###############################################################################
# Add an executable target.
# _name The executable name.
# COMPONENT The part of PCL that this library belongs to.
# SOURCES The source files for the library.
function(PCL_CUDA_ADD_EXECUTABLE _name)
  set(options)
  set(oneValueArgs COMPONENT)
  set(multiValueArgs SOURCES)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_CUDA_ADD_EXECUTABLE: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT ARGS_COMPONENT)
    message(FATAL_ERROR "PCL_CUDA_ADD_EXECUTABLE requires parameter COMPONENT.")
  endif()

  REMOVE_VTK_DEFINITIONS()

  add_executable(${_name} ${ARGS_SOURCES})

  PCL_ADD_VERSION_INFO(${_name})

  target_compile_options(${_name} PRIVATE $<$<COMPILE_LANGUAGE:CUDA>: ${GEN_CODE} --expt-relaxed-constexpr>)

  target_include_directories(${_name} PRIVATE ${CUDA_TOOLKIT_INCLUDE})

  if(WIN32 AND MSVC)
    set_target_properties(${_name} PROPERTIES DEBUG_OUTPUT_NAME ${_name}${CMAKE_DEBUG_POSTFIX}
                                              RELEASE_OUTPUT_NAME ${_name}${CMAKE_RELEASE_POSTFIX})
  endif()

  # There's a single app.
  set_target_properties(${_name} PROPERTIES FOLDER "Apps")

  set(PCL_EXECUTABLES ${PCL_EXECUTABLES} ${_name})
  install(TARGETS ${_name} RUNTIME DESTINATION ${BIN_INSTALL_DIR}
          COMPONENT pcl_${ARGS_COMPONENT})
endfunction()

###############################################################################
# Add a test target.
# _name The test name.
# _exename The exe name.
# ARGN :
#    FILES the source files for the test
#    ARGUMENTS Arguments for test executable
#    LINK_WITH link test executable with libraries
macro(PCL_ADD_TEST _name _exename)
  set(options)
  set(oneValueArgs)
  set(multiValueArgs FILES ARGUMENTS LINK_WITH)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_ADD_TEST: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  # Always create regular executable target first for compatibility
  add_executable(${_exename} ${ARGS_FILES})
  target_link_libraries(${_exename} ${ARGS_LINK_WITH} ${CLANG_LIBRARIES})
  
  if(NOT WIN32)
    set_target_properties(${_exename} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
  endif()

  target_link_libraries(${_exename} Threads::Threads ${ATOMIC_LIBRARY})
  target_link_libraries(${_exename} -L/home/uvxiao/.local/lib -llz4)
  
  # Set RPATH for portable test binaries
  set_target_properties(${_exename} PROPERTIES 
    SKIP_BUILD_RPATH FALSE
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "${CMAKE_BINARY_DIR}/lib:${FLANN_INSTALL_PATH}/lib:/home/uvxiao/.local/lib"
    INSTALL_RPATH_USE_LINK_PATH FALSE
    BUILD_RPATH_USE_ORIGIN FALSE
  )
  
  if(PCL_INSTRUMENTATION_ENABLED)
    # Create instrumented version as a separate executable
    set(instrumented_exe "${_exename}_instrumented")
    set(ll_instrumented_files "")
    
    # Convert each source file to instrumented LLVM IR
    foreach(source_file ${ARGS_FILES})
      get_filename_component(source_name ${source_file} NAME_WE)
      get_filename_component(source_dir ${source_file} DIRECTORY)
      
      # Make source path absolute if relative
      if(NOT IS_ABSOLUTE ${source_file})
        set(abs_source_file "${CMAKE_CURRENT_SOURCE_DIR}/${source_file}")
      else()
        set(abs_source_file ${source_file})
      endif()
      
      set(ll_file "${CMAKE_CURRENT_BINARY_DIR}/${source_name}.ll")
      set(ll_instrumented_file "${CMAKE_CURRENT_BINARY_DIR}/${source_name}_instrumented.ll")
      
      # Get include paths from linked libraries
      set(include_args "")
      foreach(lib ${ARGS_LINK_WITH})
        if(TARGET ${lib})
          get_target_property(lib_includes ${lib} INTERFACE_INCLUDE_DIRECTORIES)
          if(lib_includes)
            foreach(include_dir ${lib_includes})
              list(APPEND include_args "-I${include_dir}")
            endforeach()
          endif()
        endif()
      endforeach()
      
      # Add PCL and system include paths
      list(APPEND include_args 
        "-I${PROJECT_SOURCE_DIR}"
        "-I${PROJECT_BINARY_DIR}/include" 
        "-I${PROJECT_SOURCE_DIR}/test/include"
        "-I${FLANN_INSTALL_PATH}/include"
        "-I/home/uvxiao/.local/include"
        "-I/usr/include/eigen3"
        "-I${PROJECT_SOURCE_DIR}/common/include"
        "-I${PROJECT_SOURCE_DIR}/filters/include"
        "-I${PROJECT_SOURCE_DIR}/2d/include"
        "-I${PROJECT_SOURCE_DIR}/geometry/include"
        "-I${PROJECT_SOURCE_DIR}/octree/include"
        "-I${PROJECT_SOURCE_DIR}/features/include"
        "-I${PROJECT_SOURCE_DIR}/kdtree/include"
        "-I${PROJECT_SOURCE_DIR}/search/include"
        "-I${PROJECT_SOURCE_DIR}/io/include"
        "-I${PROJECT_SOURCE_DIR}/ml/include"
        "-I${PROJECT_SOURCE_DIR}/segmentation/include"
        "-I${PROJECT_SOURCE_DIR}/surface/include"
        "-I${PROJECT_SOURCE_DIR}/registration/include"
        "-I${PROJECT_SOURCE_DIR}/keypoints/include"
        "-I${PROJECT_SOURCE_DIR}/tracking/include"
        "-I${PROJECT_SOURCE_DIR}/recognition/include"
        "-I${PROJECT_SOURCE_DIR}/stereo/include"
        "-I${PROJECT_SOURCE_DIR}/sample_consensus/include"
      )
      
      # Compile to LLVM IR
      add_custom_command(
        OUTPUT ${ll_file}
        COMMAND ${CLANG}++ -S -emit-llvm -std=c++17 -fPIC -O2
               -fno-vectorize -fno-slp-vectorize -ffp-contract=off 
               -mno-avx -mno-avx2 -mno-avx512f -mno-fma
               ${include_args}
               -c ${abs_source_file} -o ${ll_file}
        DEPENDS ${abs_source_file}
        COMMENT "Generating LLVM IR for ${source_file}"
      )
      
      # Instrument LLVM IR with fast counting
      add_custom_command(
        OUTPUT ${ll_instrumented_file}
        COMMAND ${OPT} -load-pass-plugin="${PASS_PATH}" -passes=bb_instrument -just-count ${ll_file} -o ${ll_instrumented_file}
        DEPENDS ${ll_file}
        COMMENT "Instrumenting LLVM IR for ${source_file} with fast counting"
      )
      
      list(APPEND ll_instrumented_files ${ll_instrumented_file})
    endforeach()
    
    # Link instrumented LLVM IR files into a bitcode
    set(instrumented_bc "${CMAKE_CURRENT_BINARY_DIR}/${instrumented_exe}.bc")
    add_custom_command(
      OUTPUT ${instrumented_bc}
      COMMAND ${LLVM_LINK} ${ll_instrumented_files} -o ${instrumented_bc}
      DEPENDS ${ll_instrumented_files}
      COMMENT "Linking instrumented LLVM IR for ${instrumented_exe}"
    )
    
    # Create instrumented executable from bitcode with full library linking
    add_custom_command(
      OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${instrumented_exe}
      COMMAND ${CLANG}++ -fPIC -O2 -fno-vectorize -fno-slp-vectorize -ffp-contract=off 
              -mno-avx -mno-avx2 -mno-avx512f -mno-fma
              ${instrumented_bc} -o ${CMAKE_CURRENT_BINARY_DIR}/${instrumented_exe}
              -L${CMAKE_BINARY_DIR}/lib -L${FLANN_INSTALL_PATH}/lib -L/home/uvxiao/.local/lib
              -L/usr/src/gtest
              -lpcl_common -lpcl_kdtree -lpcl_octree -lpcl_search -lpcl_sample_consensus
              -lpcl_filters -lpcl_io -lpcl_io_ply -lpcl_features -lpcl_ml -lpcl_segmentation
              -lpcl_surface -lpcl_registration -lpcl_keypoints -lpcl_tracking
              -lpcl_recognition -lpcl_stereo
              -lflann_cpp -lgtest -lgtest_main -lpthread -llz4 -latomic
              -lboost_system -lboost_filesystem -lboost_thread -lboost_date_time
              -lboost_iostreams -lboost_chrono -lpng -lusb-1.0 -lz
              -Wl,-rpath,${CMAKE_BINARY_DIR}/lib:${FLANN_INSTALL_PATH}/lib:/home/uvxiao/.local/lib
      DEPENDS ${instrumented_bc} pcl_gtest pcl_common ${ARGS_LINK_WITH}
      COMMENT "Creating instrumented executable ${instrumented_exe}"
    )
    
    # Create a custom target for the instrumented executable
    add_custom_target(${instrumented_exe} ALL DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${instrumented_exe})
  endif()
  
  # Standard target configuration that works for both instrumented and non-instrumented builds

  # Generate .args file for each test executable as per INSTRUMENT.md requirements
  if(ARGS_ARGUMENTS)
    string (REPLACE ";" " " ARGS_ARGUMENTS_STR "${ARGS_ARGUMENTS}")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/${_exename}.args" "${ARGS_ARGUMENTS_STR}")
    
    #Only applies to MSVC
    if(MSVC)
      set_target_properties(${_exename} PROPERTIES VS_DEBUGGER_COMMAND_ARGUMENTS ${ARGS_ARGUMENTS_STR})
    endif()
  else()
    # Create empty .args file if no arguments
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/${_exename}.args" "")
  endif()

  if(NOT PCL_INSTRUMENTATION_ENABLED)
    # Add post-build step to fix library paths using patchelf
    if(UNIX AND NOT APPLE)
      add_custom_command(TARGET ${_exename} POST_BUILD
        COMMAND ${CMAKE_SOURCE_DIR}/../fix_binary_libs.sh $<TARGET_FILE:${_exename}> ${CMAKE_BINARY_DIR}/lib ${FLANN_INSTALL_PATH}/lib
        COMMENT "Fixing library paths for ${_exename}"
      )
    endif()

    set_target_properties(${_exename} PROPERTIES FOLDER "Tests")
  endif()
  
  # Add both regular and instrumented tests to the test framework
  if(PCL_INSTRUMENTATION_ENABLED)
    # Use instrumented version for actual testing
    set(instrumented_exe "${_exename}_instrumented")
    add_test(NAME ${_name} COMMAND ${CMAKE_CURRENT_BINARY_DIR}/${instrumented_exe} ${ARGS_ARGUMENTS})
    add_test(NAME ${_name}_regular COMMAND ${_exename} ${ARGS_ARGUMENTS})
    
    # Add both to global test dependencies
    add_dependencies(tests ${_exename})
    add_dependencies(tests ${instrumented_exe})
  else()
    add_test(NAME ${_name} COMMAND ${_exename} ${ARGS_ARGUMENTS})
    add_dependencies(tests ${_exename})
  endif()
endmacro()

###############################################################################
# Add a benchmark target.
# _name The benchmark name.
# ARGN :
#    FILES the source files for the benchmark
#    ARGUMENTS Arguments for benchmark executable
#    LINK_WITH link benchmark executable with libraries
function(PCL_ADD_BENCHMARK _name)
  set(options)
  set(oneValueArgs)
  set(multiValueArgs FILES ARGUMENTS LINK_WITH)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_ADD_BENCHMARK: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  add_executable(benchmark_${_name} ${ARGS_FILES})
  set_target_properties(benchmark_${_name} PROPERTIES FOLDER "Benchmarks")
  target_link_libraries(benchmark_${_name} benchmark::benchmark ${ARGS_LINK_WITH})
  set_target_properties(benchmark_${_name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})

  # See https://github.com/google/benchmark/issues/1457
  if(BenchmarkBuildType STREQUAL "STATIC_LIBRARY" AND benchmark_VERSION STREQUAL "1.7.0")
    target_compile_definitions(benchmark_${_name} PUBLIC -DBENCHMARK_STATIC_DEFINE)
  endif()

  #Only applies to MSVC
  if(MSVC)
    #Requires CMAKE version 3.13.0
    get_target_property(BenchmarkArgumentWarningShown run_benchmarks PCL_BENCHMARK_ARGUMENTS_WARNING_SHOWN)
    #Only add if there are arguments to test
    if(ARGS_ARGUMENTS)
      string (REPLACE ";" " " ARGS_ARGUMENTS_STR "${ARGS_ARGUMENTS}")
      set_target_properties(benchmark_${_name} PROPERTIES VS_DEBUGGER_COMMAND_ARGUMENTS ${ARGS_ARGUMENTS_STR})
    endif()
  endif()

  add_custom_target(run_benchmark_${_name} benchmark_${_name} ${ARGS_ARGUMENTS})
  set_target_properties(run_benchmark_${_name} PROPERTIES FOLDER "Benchmarks")

  add_dependencies(run_benchmarks run_benchmark_${_name})
endfunction()

###############################################################################
# Add an example target.
# _name The example name.
# ARGN :
#    FILES the source files for the example
#    LINK_WITH link example executable with libraries
macro(PCL_ADD_EXAMPLE _name)
  set(options)
  set(oneValueArgs)
  set(multiValueArgs FILES LINK_WITH)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_ADD_EXAMPLE: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  add_executable(${_name} ${ARGS_FILES})
  target_link_libraries(${_name} ${ARGS_LINK_WITH} ${CLANG_LIBRARIES})
  if(WIN32 AND MSVC)
    set_target_properties(${_name} PROPERTIES DEBUG_OUTPUT_NAME ${_name}${CMAKE_DEBUG_POSTFIX}
                                              RELEASE_OUTPUT_NAME ${_name}${CMAKE_RELEASE_POSTFIX})
  endif()
  set_target_properties(${_name} PROPERTIES FOLDER "Examples")

  # add target to list of example targets created at the parent scope
  list(APPEND PCL_EXAMPLES_ALL_TARGETS ${_name})
  set(PCL_EXAMPLES_ALL_TARGETS "${PCL_EXAMPLES_ALL_TARGETS}" PARENT_SCOPE)
endmacro()

###############################################################################
# Add compile flags to a target (because CMake doesn't provide something so
# common itself).
# _name The target name.
# _flags The new compile flags to be added, as a string.
macro(PCL_ADD_CFLAGS _name _flags)
  get_target_property(_current_flags ${_name} COMPILE_FLAGS)
  if(NOT _current_flags)
    set_target_properties(${_name} PROPERTIES COMPILE_FLAGS ${_flags})
  else()
    set_target_properties(${_name} PROPERTIES COMPILE_FLAGS "${_current_flags} ${_flags}")
  endif()
endmacro()

###############################################################################
# Add link flags to a target (because CMake doesn't provide something so
# common itself).
# _name The target name.
# _flags The new link flags to be added, as a string.
macro(PCL_ADD_LINKFLAGS _name _flags)
  get_target_property(_current_flags ${_name} LINK_FLAGS)
  if(NOT _current_flags)
      set_target_properties(${_name} PROPERTIES LINK_FLAGS ${_flags})
  else()
      set_target_properties(${_name} PROPERTIES LINK_FLAGS "${_current_flags} ${_flags}")
  endif()
endmacro()

###############################################################################
# Make a pkg-config file for a library. Do not include general PCL stuff in the
# arguments; they will be added automatically.
# _name The library name. Please prepend "pcl_" to ensure no conflicts in user systems
# COMPONENT The part of PCL that this pkg-config file belongs to.
# DESC Description of the library.
# PCL_DEPS External dependencies to pcl libs, as a list. (will get mangled to external pkg-config name)
# EXT_DEPS External dependencies, as a list.
# INT_DEPS Internal dependencies, as a list.
# CFLAGS Compiler flags necessary to build with the library.
# LIB_FLAGS Linker flags necessary to link to the library.
# HEADER_ONLY Ensures that no -L or l flags will be created.
function(PCL_MAKE_PKGCONFIG _name)
  set(options HEADER_ONLY)
  set(oneValueArgs COMPONENT DESC CFLAGS LIB_FLAGS)
  set(multiValueArgs PCL_DEPS INT_DEPS EXT_DEPS)
  cmake_parse_arguments(ARGS "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(ARGS_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unknown arguments given to PCL_MAKE_PKGCONFIG: ${ARGS_UNPARSED_ARGUMENTS}")
  endif()

  if(NOT ARGS_COMPONENT)
    message(FATAL_ERROR "PCL_MAKE_PKGCONFIG requires parameter COMPONENT.")
  endif()

  set(PKG_NAME ${_name})
  set(PKG_DESC ${ARGS_DESC})
  set(PKG_CFLAGS ${ARGS_CFLAGS})
  set(PKG_LIBFLAGS ${ARGS_LIB_FLAGS})
  LIST_TO_STRING(PKG_EXTERNAL_DEPS "${ARGS_EXT_DEPS}")
  foreach(_dep ${ARGS_PCL_DEPS})
    string(APPEND PKG_EXTERNAL_DEPS " pcl_${_dep}")
  endforeach()
  set(PKG_INTERNAL_DEPS "")
  foreach(_dep ${ARGS_INT_DEPS})
    string(APPEND PKG_INTERNAL_DEPS " -l${_dep}")
  endforeach()

  set(_pc_file ${CMAKE_CURRENT_BINARY_DIR}/${_name}.pc)
  if(ARGS_HEADER_ONLY)
    configure_file(${PROJECT_SOURCE_DIR}/cmake/pkgconfig-headeronly.cmake.in ${_pc_file} @ONLY)
  else()
    configure_file(${PROJECT_SOURCE_DIR}/cmake/pkgconfig.cmake.in ${_pc_file} @ONLY)
  endif()
  install(FILES ${_pc_file}
          DESTINATION ${PKGCFG_INSTALL_DIR}
          COMPONENT pcl_${ARGS_COMPONENT})
endfunction()

###############################################################################
# PRIVATE

###############################################################################
# Reset the subsystem status map.
macro(PCL_RESET_MAPS)
  foreach(_ss ${PCL_SUBSYSTEMS})
    string(TOUPPER "PCL_${_ss}_SUBSYS" PCL_SUBSYS_SUBSYS)
    if(${PCL_SUBSYS_SUBSYS})
      string(TOUPPER "PCL_${_ss}_SUBSYS_DESC" PCL_PARENT_SUBSYS_DESC)
      set(${PCL_SUBSYS_SUBSYS_DESC} "" CACHE INTERNAL "" FORCE)
      set(${PCL_SUBSYS_SUBSYS} "" CACHE INTERNAL "" FORCE)
    endif()
  endforeach()

  set(PCL_SUBSYS_HYPERSTATUS "" CACHE INTERNAL "To Build Or Not To Build, That Is The Question." FORCE)
  set(PCL_SUBSYS_STATUS "" CACHE INTERNAL "To build or not to build, that is the question." FORCE)
  set(PCL_SUBSYS_REASONS "" CACHE INTERNAL "But why?" FORCE)
  set(PCL_SUBSYS_DEPS "" CACHE INTERNAL "A depends on B and C." FORCE)
  set(PCL_SUBSYS_EXT_DEPS "" CACHE INTERNAL "A depends on B and C." FORCE)
  set(PCL_SUBSYS_OPT_DEPS "" CACHE INTERNAL "A depends on B and C." FORCE)
  set(PCL_SUBSYSTEMS "" CACHE INTERNAL "Internal list of subsystems" FORCE)
  set(PCL_SUBSYS_DESC "" CACHE INTERNAL "Subsystem descriptions" FORCE)
endmacro()

###############################################################################
# Register a subsystem.
# _name Subsystem name.
# _desc Description of the subsystem
macro(PCL_ADD_SUBSYSTEM _name _desc)
  set(_temp ${PCL_SUBSYSTEMS})
  list(APPEND _temp ${_name})
  set(PCL_SUBSYSTEMS ${_temp} CACHE INTERNAL "Internal list of subsystems" FORCE)
  SET_IN_GLOBAL_MAP(PCL_SUBSYS_DESC ${_name} ${_desc})
endmacro()

###############################################################################
# Register a subsubsystem.
# _name Subsystem name.
# _desc Description of the subsystem
macro(PCL_ADD_SUBSUBSYSTEM _parent _name _desc)
  string(TOUPPER "PCL_${_parent}_SUBSYS" PCL_PARENT_SUBSYS)
  string(TOUPPER "PCL_${_parent}_SUBSYS_DESC" PCL_PARENT_SUBSYS_DESC)
  set(_temp ${${PCL_PARENT_SUBSYS}})
  list(APPEND _temp ${_name})
  set(${PCL_PARENT_SUBSYS} ${_temp} CACHE INTERNAL "Internal list of ${_parenr} subsystems" FORCE)
  set_in_global_map(${PCL_PARENT_SUBSYS_DESC} ${_name} ${_desc})
endmacro()

###############################################################################
# Set the status of a subsystem.
# _name Subsystem name.
# _status TRUE if being built, FALSE otherwise.
# ARGN[0] Reason for not building.
macro(PCL_SET_SUBSYS_STATUS _name _status)
  if(${ARGC} EQUAL 3)
    set(_reason ${ARGV2})
  else()
    set(_reason "No reason provided")
  endif()
  SET_IN_GLOBAL_MAP(PCL_SUBSYS_STATUS ${_name} ${_status})
  SET_IN_GLOBAL_MAP(PCL_SUBSYS_REASONS ${_name} ${_reason})
endmacro()

###############################################################################
# Set the status of a subsystem.
# _name Subsystem name.
# _status TRUE if being built, FALSE otherwise.
# ARGN[0] Reason for not building.
macro(PCL_SET_SUBSUBSYS_STATUS _parent _name _status)
  if(${ARGC} EQUAL 4)
    set(_reason ${ARGV2})
  else()
    set(_reason "No reason provided")
  endif()
  SET_IN_GLOBAL_MAP(PCL_SUBSYS_STATUS ${_parent}_${_name} ${_status})
  SET_IN_GLOBAL_MAP(PCL_SUBSYS_REASONS ${_parent}_${_name} ${_reason})
endmacro()

###############################################################################
# Get the status of a subsystem
# _var Destination variable.
# _name Name of the subsystem.
macro(PCL_GET_SUBSYS_STATUS _var _name)
  GET_IN_MAP(${_var} PCL_SUBSYS_STATUS ${_name})
endmacro()

###############################################################################
# Get the status of a subsystem
# _var Destination variable.
# _name Name of the subsystem.
macro(PCL_GET_SUBSUBSYS_STATUS _var _parent _name)
    GET_IN_MAP(${_var} PCL_SUBSYS_STATUS ${_parent}_${_name})
endmacro()

###############################################################################
# Set the hyperstatus of a subsystem and its dependee
# _name Subsystem name.
# _dependee Dependent subsystem.
# _status AUTO_OFF to disable AUTO_ON to enable
# ARGN[0] Reason for not building.
macro(PCL_SET_SUBSYS_HYPERSTATUS _name _dependee _status)
  SET_IN_GLOBAL_MAP(PCL_SUBSYS_HYPERSTATUS ${_name}_${_dependee} ${_status})
  if(${ARGC} EQUAL 4)
    SET_IN_GLOBAL_MAP(PCL_SUBSYS_REASONS ${_dependee} ${ARGV3})
  endif()
endmacro()

###############################################################################
# Get the hyperstatus of a subsystem and its dependee
# _name IN subsystem name.
# _dependee IN dependent subsystem.
# _var OUT hyperstatus
# ARGN[0] Reason for not building.
macro(PCL_GET_SUBSYS_HYPERSTATUS _var _name)
  set(${_var} "AUTO_ON")
  if(${ARGC} EQUAL 3)
    GET_IN_MAP(${_var} PCL_SUBSYS_HYPERSTATUS ${_name}_${ARGV2})
  else()
    foreach(subsys ${PCL_SUBSYS_DEPS_${_name}})
      if("${PCL_SUBSYS_HYPERSTATUS_${subsys}_${_name}}" STREQUAL "AUTO_OFF")
        set(${_var} "AUTO_OFF")
        break()
      endif()
    endforeach()
  endif()
endmacro()

###############################################################################
# Set the hyperstatus of a subsystem and its dependee
macro(PCL_UNSET_SUBSYS_HYPERSTATUS _name _dependee)
  unset(PCL_SUBSYS_HYPERSTATUS_${_name}_${dependee})
endmacro()

###############################################################################
# Set the include directory name of a subsystem.
# _name Subsystem name.
# _includedir Name of subdirectory for includes
# ARGN[0] Reason for not building.
macro(PCL_SET_SUBSYS_INCLUDE_DIR _name _includedir)
  SET_IN_GLOBAL_MAP(PCL_SUBSYS_INCLUDE ${_name} ${_includedir})
endmacro()

###############################################################################
# Get the include directory name of a subsystem - return _name if not set
# _var Destination variable.
# _name Name of the subsystem.
macro(PCL_GET_SUBSYS_INCLUDE_DIR _var _name)
  GET_IN_MAP(${_var} PCL_SUBSYS_INCLUDE ${_name})
  if(NOT ${_var})
    set(${_var} ${_name})
  endif()
endmacro()

###############################################################################
# Write a report on the build/not-build status of the subsystems
macro(PCL_WRITE_STATUS_REPORT)
  message(STATUS "PCL build with following flags:")
  message(STATUS "${CMAKE_CXX_FLAGS}")
  message(STATUS "The following subsystems will be built:")
  foreach(_ss ${PCL_SUBSYSTEMS})
    PCL_GET_SUBSYS_STATUS(_status ${_ss})
    if(_status)
      set(message_text "  ${_ss}")
      string(TOUPPER "PCL_${_ss}_SUBSYS" PCL_SUBSYS_SUBSYS)
      if(${PCL_SUBSYS_SUBSYS})
        set(will_build)
        foreach(_sub ${${PCL_SUBSYS_SUBSYS}})
          PCL_GET_SUBSYS_STATUS(_sub_status ${_ss}_${_sub})
          if(_sub_status)
            string(APPEND will_build "\n       |_ ${_sub}")
          endif()
        endforeach()
        if(NOT ("${will_build}" STREQUAL ""))
          string(APPEND message_text "\n       building: ${will_build}")
        endif()
        set(wont_build)
        foreach(_sub ${${PCL_SUBSYS_SUBSYS}})
          PCL_GET_SUBSYS_STATUS(_sub_status ${_ss}_${_sub})
          PCL_GET_SUBSYS_HYPERSTATUS(_sub_hyper_status ${_ss}_${sub})
          if(NOT _sub_status OR ("${_sub_hyper_status}" STREQUAL "AUTO_OFF"))
            GET_IN_MAP(_reason PCL_SUBSYS_REASONS ${_ss}_${_sub})
            string(APPEND wont_build "\n       |_ ${_sub}: ${_reason}")
          endif()
        endforeach()
        if(NOT ("${wont_build}" STREQUAL ""))
          string(APPEND message_text "\n       not building: ${wont_build}")
        endif()
      endif()
      message(STATUS "${message_text}")
    endif()
  endforeach()

  message(STATUS "The following subsystems will not be built:")
  foreach(_ss ${PCL_SUBSYSTEMS})
    PCL_GET_SUBSYS_STATUS(_status ${_ss})
    PCL_GET_SUBSYS_HYPERSTATUS(_hyper_status ${_ss})
    if(NOT _status OR ("${_hyper_status}" STREQUAL "AUTO_OFF"))
       GET_IN_MAP(_reason PCL_SUBSYS_REASONS ${_ss})
       message(STATUS "  ${_ss}: ${_reason}")
    endif()
  endforeach()
endmacro()

##############################################################################
# Collect subdirectories from dirname that contains filename and store them in
#  varname.
# WARNING If extra arguments are given then they are considered as exception
# list and varname will contain subdirectories of dirname that contains
# fielename but doesn't belong to exception list.
# dirname IN parent directory
# filename IN file name to look for in each subdirectory of parent directory
# varname OUT list of subdirectories containing filename
# exception_list OPTIONAL and contains list of subdirectories not to account
macro(collect_subproject_directory_names dirname filename names dirs)
  file(GLOB globbed RELATIVE "${dirname}" "${dirname}/*/${filename}")
  if(${ARGC} GREATER 4)
    set(exclusion_list ${ARGN})
    foreach(file ${globbed})
      get_filename_component(dir ${file} PATH)
      list(FIND exclusion_list ${dir} excluded)
      if(excluded EQUAL -1)
        set(${dirs} ${${dirs}} ${dir})
      endif()
    endforeach()
  else()
    foreach(file ${globbed})
      get_filename_component(dir ${file} PATH)
      set(${dirs} ${${dirs}} ${dir})
    endforeach()
  endif()
  foreach(subdir ${${dirs}})
    file(STRINGS ${dirname}/${subdir}/CMakeLists.txt name REGEX "[setSET ]+\\(.*SUBSYS_NAME .*\\)$")
    string(REGEX REPLACE "[setSET ]+\\(.*SUBSYS_NAME[ ]+([A-Za-z0-9_]+)[ ]*\\)" "\\1" name "${name}")
    set(${names} ${${names}} ${name})
    file(STRINGS ${dirname}/${subdir}/CMakeLists.txt DEPENDENCIES REGEX "set.*SUBSYS_DEPS .*\\)")
    string(REGEX REPLACE "set.*SUBSYS_DEPS" "" DEPENDENCIES "${DEPENDENCIES}")
    string(REPLACE ")" "" DEPENDENCIES "${DEPENDENCIES}")
    string(STRIP "${DEPENDENCIES}" DEPENDENCIES)
    string(REPLACE " " ";" DEPENDENCIES "${DEPENDENCIES}")
    if(NOT("${DEPENDENCIES}" STREQUAL ""))
      list(REMOVE_ITEM DEPENDENCIES "#")
      string(TOUPPER "PCL_${name}_DEPENDS" SUBSYS_DEPENDS)
      set(${SUBSYS_DEPENDS} ${DEPENDENCIES})
      foreach(dependee ${DEPENDENCIES})
        string(TOUPPER "PCL_${dependee}_DEPENDIES" SUBSYS_DEPENDIES)
        set(${SUBSYS_DEPENDIES} ${${SUBSYS_DEPENDIES}} ${name})
      endforeach()
    endif()
  endforeach()
endmacro()

########################################################################################
# Macro to disable subsystem dependies
# _subsys IN subsystem name
macro(PCL_DISABLE_DEPENDIES _subsys)
  string(TOUPPER "pcl_${_subsys}_dependies" PCL_SUBSYS_DEPENDIES)
  if(NOT ("${${PCL_SUBSYS_DEPENDIES}}" STREQUAL ""))
    foreach(dep ${${PCL_SUBSYS_DEPENDIES}})
      PCL_SET_SUBSYS_HYPERSTATUS(${_subsys} ${dep} AUTO_OFF "Disabled: ${_subsys} missing.")
      set(BUILD_${dep} OFF CACHE BOOL "Disabled: ${_subsys} missing." FORCE)
    endforeach()
  endif()
endmacro()

########################################################################################
# Macro to enable subsystem dependies
# _subsys IN subsystem name
macro(PCL_ENABLE_DEPENDIES _subsys)
  string(TOUPPER "pcl_${_subsys}_dependies" PCL_SUBSYS_DEPENDIES)
  if(NOT ("${${PCL_SUBSYS_DEPENDIES}}" STREQUAL ""))
    foreach(dep ${${PCL_SUBSYS_DEPENDIES}})
      PCL_GET_SUBSYS_HYPERSTATUS(dependee_status ${_subsys} ${dep})
      if("${dependee_status}" STREQUAL "AUTO_OFF")
        PCL_SET_SUBSYS_HYPERSTATUS(${_subsys} ${dep} AUTO_ON)
        GET_IN_MAP(desc PCL_SUBSYS_DESC ${dep})
        set(BUILD_${dep} ON CACHE BOOL "${desc}" FORCE)
      endif()
    endforeach()
  endif()
endmacro()

########################################################################################
# Macro to build subsystem centric documentation
# _subsys IN the name of the subsystem to generate documentation for
macro (PCL_ADD_DOC _subsys)
  string(TOUPPER "${_subsys}" SUBSYS)
  set(doc_subsys "doc_${_subsys}")
  GET_IN_MAP(dependencies PCL_SUBSYS_DEPS ${_subsys})
  if(DOXYGEN_FOUND)
    if(HTML_HELP_COMPILER)
      set(DOCUMENTATION_HTML_HELP YES)
    else()
      set(DOCUMENTATION_HTML_HELP NO)
    endif()
    if(DOXYGEN_DOT_EXECUTABLE)
      set(HAVE_DOT YES)
    else()
      set(HAVE_DOT NO)
    endif()
    if(NOT "${dependencies}" STREQUAL "")
      set(STRIPPED_HEADERS "${PCL_SOURCE_DIR}/${dependencies}/include")
      string(REPLACE ";" "/include \\\n                         ${PCL_SOURCE_DIR}/"
             STRIPPED_HEADERS "${STRIPPED_HEADERS}")
    endif()
    set(DOC_SOURCE_DIR "\"${CMAKE_CURRENT_SOURCE_DIR}\"\\")
    foreach(dep ${dependencies})
      string(APPEND DOC_SOURCE_DIR "\n\t\t\t\t\t\t\t\t\t\t\t\t \"${PCL_SOURCE_DIR}/${dep}\"\\")
    endforeach()
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/html")
    set(doxyfile "${CMAKE_CURRENT_BINARY_DIR}/doxyfile")
    configure_file("${PCL_SOURCE_DIR}/doc/doxygen/doxyfile.in" ${doxyfile})
    add_custom_target(${doc_subsys} ${DOXYGEN_EXECUTABLE} ${doxyfile})
    set_target_properties(${doc_subsys} PROPERTIES FOLDER "Documentation")
  endif()
endmacro()

###############################################################################
# Add a dependency for a grabber
# _name The dependency name.
# _description The description text to display when dependency is not found.
# This macro adds on option named "WITH_NAME", where NAME is the capitalized
# dependency name. The user may use this option to control whether the
# corresponding grabber should be built or not. Also an attempt to find a
# package with the given name is made. If it is not successful, then the
# "WITH_NAME" option is coerced to FALSE.
macro(PCL_ADD_GRABBER_DEPENDENCY _name _description)
  string(TOUPPER ${_name} _name_capitalized)
  option(WITH_${_name_capitalized} "${_description}" TRUE)
  if(WITH_${_name_capitalized})
    find_package(${_name})
    if(NOT ${_name_capitalized}_FOUND)
      set(WITH_${_name_capitalized} FALSE CACHE BOOL "${_description}" FORCE)
      message(STATUS "${_description}: not building because ${_name} not found")
    else()
      set(HAVE_${_name_capitalized} TRUE)
      include_directories(SYSTEM "${${_name_capitalized}_INCLUDE_DIRS}")
    endif()
  endif()
endmacro()

###############################################################################
# Set the dependencies for a specific test module on the provided variable
# _var The variable to be filled with the dependencies
# _module The module name
macro(PCL_SET_TEST_DEPENDENCIES _var _module)
  set(${_var} global_tests ${_module} ${PCL_SUBSYS_DEPS_${_module}})
endmacro()

###############################################################################
# Add two test targets for both values of PCL_RUN_TESTS_AT_COMPILE_TIME 
# boolean flag, binaries produced are named with "_runtime" and "_compiletime" 
# for false and true values accordingly.
# _name The test name.
# _exename The exe name.
# ARGN :
#    see PCL_ADD_TEST documentation
macro (PCL_ADD_COMPILETIME_AND_RUNTIME_TEST _name _exename)
  PCL_ADD_TEST("${_name}_runtime" "${_exename}_runtime" ${ARGN})
  target_compile_definitions("${_exename}_runtime" PRIVATE PCL_RUN_TESTS_AT_COMPILE_TIME=false)
  PCL_ADD_TEST("${_name}_compiletime" "${_exename}_compiletime" ${ARGN})
  target_compile_definitions("${_exename}_compiletime" PRIVATE PCL_RUN_TESTS_AT_COMPILE_TIME=true)
endmacro()
