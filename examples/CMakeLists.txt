set(SUBSYS_NAME examples)
set(SUBSYS_DESC "PCL examples")
set(SUBSYS_DEPS common io features search kdtree octree filters keypoints segmentation sample_consensus outofcore stereo geometry surface)

PCL_SUBSYS_OPTION(build ${SUBSYS_NAME} ${SUBSYS_DESC} OFF)
PCL_SUBSYS_DEPEND(build NAME ${SUBSYS_NAME} DEPS ${SUBSYS_DEPS})

if(NOT build)
  return()
endif()

# this variable will filled with all targets added with pcl_add_example
set(PCL_EXAMPLES_ALL_TARGETS)

# This looks for all examples/XXX/CMakeLists.txt
file (GLOB examples_sbudirs */CMakeLists.txt)
# Extract only relevant XXX and append it to PCL_EXAMPLES_SUBDIRS
foreach(subdir ${examples_sbudirs})
  # PATH of get_filename_component has problem dealing with windows shared folders "//xxx.xxx.xxx.xxx/folder"
  # Check here for the discussion: http://www.pcl-developers.org/Small-hack-to-get-filename-component-td5706691.html
  # Modified by Yangyan Li(yangyan.lee@gmail.com)
  # get_filename_component (dir ${subdir} PATH)
  get_filename_component (absolute ${subdir} ABSOLUTE)
  get_filename_component (name ${subdir} NAME)
  STRING(REGEX REPLACE ${name} "" dir ${absolute})
  list(APPEND PCL_EXAMPLES_SUBDIRS ${dir})
endforeach()

# Add the subdirectories
foreach(subdir ${PCL_EXAMPLES_SUBDIRS})
  add_subdirectory(${subdir})
endforeach()

if(CMAKE_GENERATOR_IS_IDE)
  set(SUBSYS_TARGET_NAME EXAMPLES_BUILD)
else()
  set(SUBSYS_TARGET_NAME ${SUBSYS_NAME})
endif()
add_custom_target(${SUBSYS_TARGET_NAME} DEPENDS ${PCL_EXAMPLES_ALL_TARGETS})
set_target_properties(${SUBSYS_TARGET_NAME} PROPERTIES FOLDER "Examples")

# ISAMORE LLVM IR generation for examples
if(PCL_ENABLE_LLVM_IR)
  # Function to add LLVM IR generation for an example
  function(PCL_ADD_EXAMPLE_LLVM_IR name)
    set(example_src "${CMAKE_CURRENT_SOURCE_DIR}/${name}.cpp")
    if(NOT EXISTS ${example_src})
      return()
    endif()
    
    # Create LLVM directory for examples
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/examples/llvm")
    
    # Get include directories
    get_target_property(inc_dirs ${name} INCLUDE_DIRECTORIES)
    set(include_dirs "")
    foreach(inc ${inc_dirs})
      set(include_dirs "${include_dirs} -I${inc}")
    endforeach()
    # Add PCL includes
    set(include_dirs "${include_dirs} -I${PCL_SOURCE_DIR}/common/include")
    foreach(module ${PCL_MODULES_NAMES})
      if(EXISTS "${PCL_SOURCE_DIR}/${module}/include")
        set(include_dirs "${include_dirs} -I${PCL_SOURCE_DIR}/${module}/include")
      endif()
    endforeach()
    
    # Add definitions
    set(definitions "-DPCL_NO_PRECOMPILE")
    
    # Generate LLVM IR
    add_custom_command(
      OUTPUT ${CMAKE_BINARY_DIR}/examples/llvm/${name}.ll
      COMMAND ${CMAKE_BINARY_DIR}/compile_pcl_to_ll.sh
              ${example_src}
              ${CMAKE_BINARY_DIR}/examples/llvm/${name}.ll
              "${include_dirs}"
              "${definitions}"
      DEPENDS ${example_src} ${CMAKE_BINARY_DIR}/compile_pcl_to_ll.sh
      COMMENT "Generating LLVM IR for example ${name}"
    )
    
    # Instrument the example
    add_custom_command(
      OUTPUT ${CMAKE_BINARY_DIR}/examples/llvm/${name}_instrumented.ll
      COMMAND ${OPT} -load-pass-plugin="${PASS_PATH}" -passes=bb_instrument
              ${CMAKE_BINARY_DIR}/examples/llvm/${name}.ll
              -o ${CMAKE_BINARY_DIR}/examples/llvm/${name}_instrumented.ll 2>/dev/null || touch ${CMAKE_BINARY_DIR}/examples/llvm/${name}_instrumented.ll
      DEPENDS ${CMAKE_BINARY_DIR}/examples/llvm/${name}.ll
      COMMENT "Instrumenting LLVM IR for example ${name}"
    )
    
    # Get linked libraries
    get_target_property(link_libs ${name} LINK_LIBRARIES)
    set(module_bcs "")
    foreach(lib ${link_libs})
      if(lib MATCHES "^pcl_")
        string(REPLACE "pcl_" "" module ${lib})
        if(EXISTS "${CMAKE_BINARY_DIR}/llvm/${module}_instrumented.bc")
          list(APPEND module_bcs "${CMAKE_BINARY_DIR}/llvm/${module}_instrumented.bc")
        endif()
      endif()
    endforeach()
    
    # Link with PCL modules and create instrumented executable
    if(module_bcs)
      add_custom_command(
        OUTPUT ${CMAKE_BINARY_DIR}/examples/${name}_instrumented
        COMMAND ${LLVM_LINK} ${CMAKE_BINARY_DIR}/examples/llvm/${name}_instrumented.ll ${module_bcs}
                -o ${CMAKE_BINARY_DIR}/examples/llvm/${name}_linked.bc
        COMMAND ${CLANG} ${CMAKE_BINARY_DIR}/examples/llvm/${name}_linked.bc
                -o ${CMAKE_BINARY_DIR}/examples/${name}_instrumented
                -lm -lpthread -lboost_system -lboost_filesystem -lboost_thread -lboost_date_time -lboost_iostreams -lboost_chrono -lboost_atomic -lboost_regex
                -L${PCL_BINARY_DIR}/lib
        DEPENDS ${CMAKE_BINARY_DIR}/examples/llvm/${name}_instrumented.ll ${module_bcs}
        COMMENT "Building instrumented executable: ${name}_instrumented"
      )
      
      add_custom_target(${name}_instrumented_exe ALL
        DEPENDS ${CMAKE_BINARY_DIR}/examples/${name}_instrumented
      )
    endif()
  endfunction()
  
  # Macro to add example with instrumentation
  macro(PCL_ADD_EXAMPLE_WITH_INSTRUMENTATION name)
    # Parse arguments
    set(options)
    set(oneValueArgs)
    set(multiValueArgs FILES LINK_WITH)
    cmake_parse_arguments(PCLEXAMPLE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    # Call original PCL_ADD_EXAMPLE
    PCL_ADD_EXAMPLE(${name} FILES ${PCLEXAMPLE_FILES} LINK_WITH ${PCLEXAMPLE_LINK_WITH})
    
    # Add LLVM IR generation if enabled
    if(PCL_ENABLE_LLVM_IR)
      PCL_ADD_EXAMPLE_LLVM_IR(${name})
    endif()
  endmacro()
else()
  # Define macro as alias when instrumentation is disabled
  macro(PCL_ADD_EXAMPLE_WITH_INSTRUMENTATION name)
    PCL_ADD_EXAMPLE(${name} ${ARGN})
  endmacro()
endif()
