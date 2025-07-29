set(SUBSYS_NAME global_tests)
set(SUBSYS_DESC "Point cloud library global unit tests")

PCL_SUBSYS_OPTION(build "${SUBSYS_NAME}" "${SUBSYS_DESC}" OFF)
PCL_SUBSYS_DEPEND(build NAME ${SUBSYS_NAME} DEPS ${SUBSYS_DEPS} OPT_DEPS ${OPT_DEPS})

if(NOT build)
  return()
endif()

find_package(GTestSource REQUIRED)
include_directories(SYSTEM ${GTEST_INCLUDE_DIRS} ${GTEST_SRC_DIR})

add_library(pcl_gtest STATIC ${GTEST_SRC_DIR}/src/gtest-all.cc)
target_include_directories(pcl_gtest PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)

enable_testing()

# VS needs -C config to run correct
if(MSVC)
  set(PCL_CTEST_ARGUMENTS ${PCL_CTEST_ARGUMENTS} -C $<$<CONFIG:Debug>:Debug>$<$<CONFIG:Release>:Release>)
endif()

# Enables you to disable visualization tests. Used on CI.
if(PCL_DISABLE_VISUALIZATION_TESTS)
  list(APPEND EXCLUDE_TESTS visualization)
endif()

# Enables you to disable GPU tests. Used on CI as it has no access to GPU hardware
if(PCL_DISABLE_GPU_TESTS)
  list(APPEND EXCLUDE_TESTS gpu)
endif()

#Check if there are any tests to exclude
if(EXCLUDE_TESTS)
  message(STATUS "Tests excluded: ${EXCLUDE_TESTS}")
  string(REPLACE ";" "|" EXCLUDE_TESTS_REGEX "${EXCLUDE_TESTS}")
  set(PCL_CTEST_ARGUMENTS ${PCL_CTEST_ARGUMENTS} -E "(${EXCLUDE_TESTS_REGEX})")
endif()

add_custom_target(tests "${CMAKE_CTEST_COMMAND}" ${PCL_CTEST_ARGUMENTS} -V -T Test VERBATIM)

set_target_properties(tests PROPERTIES FOLDER "Tests")

# ISAMORE LLVM IR generation for tests - Define functions/macros before subdirectories
if(PCL_ENABLE_LLVM_IR)
  # Set LLVM tool paths
  set(LLVM_LINK "/home/uvxiao/repos/jlm/build-llvm-mlir/bin/llvm-link")
  set(OPT "/home/uvxiao/repos/jlm/build-llvm-mlir/bin/opt")
  set(CLANG "/home/uvxiao/repos/jlm/build-llvm-mlir/bin/clang++")
  set(PASS_PATH "/home/uvxiao/profiler/build/lib/libbb_instrument.so")
  
  # Function to create instrumented version of a test executable
  function(PCL_ADD_TEST_INSTRUMENTED test_name)
    # Skip fuzz, gpu, and visualization tests
    if(test_name MATCHES "fuzz|gpu|visualization")
      return()
    endif()
    
    if(NOT TARGET ${test_name})
      message(WARNING "Target ${test_name} does not exist, skipping instrumentation")
      return()
    endif()
    
    # Get source files from the target
    get_target_property(test_sources ${test_name} SOURCES)
    if(NOT test_sources)
      message(WARNING "Could not get sources for ${test_name}")
      return()
    endif()
    
    # Create instrumented target name
    set(instrumented_target "${test_name}_instrumented")
    set(instrumented_exe "${CMAKE_CURRENT_BINARY_DIR}/${instrumented_target}")
    
    # Get properties from original target
    get_target_property(link_libs ${test_name} LINK_LIBRARIES)
    
    # Now we need to intercept the build process to add instrumentation
    # Step 1: Compile to LLVM bitcode instead of object files
    set(bc_files "")
    set(llvm_dir "${CMAKE_CURRENT_BINARY_DIR}/llvm")
    file(MAKE_DIRECTORY "${llvm_dir}")
    
    foreach(source ${test_sources})
      get_filename_component(source_abs ${source} ABSOLUTE)
      get_filename_component(source_name ${source} NAME_WE)
      # Make output file unique by including the test name to avoid conflicts
      set(bc_file "${llvm_dir}/${test_name}_${source_name}.bc")
      
      # Build include directories string as a list first
      set(include_dirs_list "")
      # Add PCL module includes
      foreach(module common io filters features kdtree octree search sample_consensus surface registration recognition segmentation ml geometry keypoints)
        if(EXISTS "${PCL_SOURCE_DIR}/${module}/include")
          list(APPEND include_dirs_list "-I${PCL_SOURCE_DIR}/${module}/include")
        endif()
      endforeach()
      # Add other necessary includes
      list(APPEND include_dirs_list "-I${CMAKE_BINARY_DIR}/include")
      list(APPEND include_dirs_list "-I${CMAKE_CURRENT_SOURCE_DIR}/include")
      list(APPEND include_dirs_list "-I${PCL_SOURCE_DIR}/test/include")
      list(APPEND include_dirs_list "-I${GTEST_INCLUDE_DIRS}")
      # Add Eigen3 include directory
      list(APPEND include_dirs_list "-I/usr/include/eigen3")
      if(Boost_INCLUDE_DIRS)
        list(APPEND include_dirs_list "-I${Boost_INCLUDE_DIRS}")
      endif()
      if(FLANN_INCLUDE_DIRS)
        list(APPEND include_dirs_list "-I${FLANN_INCLUDE_DIRS}")
      endif()
      
      # Convert list to space-separated string without escaping
      set(include_flags "")
      foreach(inc_dir ${include_dirs_list})
        set(include_flags "${include_flags} ${inc_dir}")
      endforeach()
      string(STRIP "${include_flags}" include_flags)
      
      # Get compile definitions from original target
      get_target_property(comp_defs ${test_name} COMPILE_DEFINITIONS)
      set(definition_flags_list "")
      if(comp_defs)
        foreach(def ${comp_defs})
          list(APPEND definition_flags_list "-D${def}")
        endforeach()
      endif()
      
      # Convert list to space-separated string without escaping
      set(definition_flags "")
      foreach(def_flag ${definition_flags_list})
        set(definition_flags "${definition_flags} ${def_flag}")
      endforeach()
      string(STRIP "${definition_flags}" definition_flags)
      
      # Custom command to compile to bitcode
      add_custom_command(
        OUTPUT ${bc_file}
        COMMAND ${CLANG} 
          -c -emit-llvm 
          -std=c++17 -O2 -fPIC
          ${include_dirs_list}
          ${definition_flags_list}
          -o ${bc_file}
          ${source_abs}
        DEPENDS ${source}
        COMMENT "Compiling ${source} to LLVM bitcode for ${test_name}"
      )
      list(APPEND bc_files ${bc_file})
    endforeach()
    
    # Step 2: Get all PCL module bitcode files that this test depends on
    set(pcl_bc_files "")
    
    # Add FLANN bitcode if needed
    if("${link_libs}" MATCHES "flann")
      set(flann_bc "${CMAKE_BINARY_DIR}/../pcl/3rdParty/Flann/build/llvm/flann.bc")
      if(EXISTS ${flann_bc})
        list(APPEND pcl_bc_files ${flann_bc})
      endif()
    endif()
    
    # Add PCL module bitcode files
    foreach(lib ${link_libs})
      if(lib MATCHES "^pcl_")
        string(REPLACE "pcl_" "" module ${lib})
        set(module_bc "${CMAKE_BINARY_DIR}/llvm/${module}.bc")
        if(EXISTS ${module_bc} OR TARGET pcl_${module}_llvm_ir)
          list(APPEND pcl_bc_files ${module_bc})
        endif()
      endif()
    endforeach()
    
    # Step 3: Link all bitcode files
    set(linked_bc "${llvm_dir}/${test_name}_linked.bc")
    add_custom_command(
      OUTPUT ${linked_bc}
      COMMAND ${LLVM_LINK} ${bc_files} ${pcl_bc_files} -o ${linked_bc}
      DEPENDS ${bc_files} ${pcl_bc_files}
      COMMENT "Linking bitcode for ${test_name}"
    )
    
    # Step 4: Instrument the linked bitcode
    set(instrumented_bc "${llvm_dir}/${test_name}_instrumented.bc")
    add_custom_command(
      OUTPUT ${instrumented_bc}
      COMMAND ${OPT} -load-pass-plugin=${PASS_PATH} -passes=bb_instrument ${linked_bc} -o ${instrumented_bc}
      DEPENDS ${linked_bc}
      COMMENT "Instrumenting ${test_name}"
    )
    
    # Step 5: Build the final executable
    # We need to get all the link flags and libraries from the original target
    set(link_flags "")
    get_target_property(link_options ${test_name} LINK_OPTIONS)
    if(link_options)
      set(link_flags ${link_options})
    endif()
    
    # Get the link libraries in the correct format
    set(link_libs_expanded "")
    foreach(lib ${link_libs})
      if(TARGET ${lib})
        # Special handling for interface libraries
        if(lib STREQUAL "Threads::Threads")
          # Skip - will add pthread manually
        elseif(lib STREQUAL "pcl_gtest")
          list(APPEND link_libs_expanded "${CMAKE_BINARY_DIR}/lib/libpcl_gtest.a")
        else()
          # Check if it's an interface library
          get_target_property(target_type ${lib} TYPE)
          if(target_type STREQUAL "INTERFACE_LIBRARY")
            # Skip interface libraries
          else()
            # It's a regular library target - use library name
            if(lib MATCHES "^pcl_")
              list(APPEND link_libs_expanded "-l${lib}")
            else()
              list(APPEND link_libs_expanded "${lib}")
            endif()
          endif()
        endif()
      else()
        # It's a library name or flag
        if(lib MATCHES "^-")
          # It's already a flag (like -lpthread)
          list(APPEND link_libs_expanded "${lib}")
        elseif(lib MATCHES "^/")
          # It's a full path
          list(APPEND link_libs_expanded "${lib}")
        else()
          # It's a library name without -l prefix
          list(APPEND link_libs_expanded "-l${lib}")
        endif()
      endif()
    endforeach()
    
    # Filter link_libs to only include actual targets for DEPENDS
    set(target_depends "")
    foreach(lib ${link_libs})
      if(TARGET ${lib})
        list(APPEND target_depends ${lib})
      endif()
    endforeach()
    
    # Custom command to build the instrumented executable
    add_custom_command(
      OUTPUT ${instrumented_exe}
      COMMAND ${CLANG}
        ${instrumented_bc}
        -o ${instrumented_exe}
        ${link_flags}
        ${link_libs_expanded}
        -L${CMAKE_BINARY_DIR}/lib
        -L$ENV{HOME}/.local/lib
        -L/home/uvxiao/boost_1_88_0/install/lib
        -L/home/uvxiao/isaegg/tests/pcl-tests/pcl/3rdParty/Flann/install/lib
        -Wl,-rpath,${CMAKE_BINARY_DIR}/lib
        -Wl,-rpath,$ENV{HOME}/.local/lib
        -Wl,-rpath,/home/uvxiao/boost_1_88_0/install/lib
        -lflann -lflann_cpp -lpthread -lm -lstdc++ -lz -llz4 -lgomp
        /usr/lib/x86_64-linux-gnu/libgtest.a
        /usr/lib/x86_64-linux-gnu/libgtest_main.a
        -lboost_system -lboost_filesystem -lboost_thread -lboost_date_time 
        -lboost_iostreams -lboost_chrono -lboost_atomic -lboost_regex
      DEPENDS ${instrumented_bc} ${target_depends}
      COMMENT "Building instrumented executable ${instrumented_target}"
      COMMAND_EXPAND_LISTS
    )
    
    # Create a custom target for the instrumented executable (not built by default)
    add_custom_target(${instrumented_target}
      DEPENDS ${instrumented_exe}
    )
    
    # Add to a special instrumented tests target
    if(NOT TARGET instrumented_tests)
      add_custom_target(instrumented_tests)
    endif()
    add_dependencies(instrumented_tests ${instrumented_target})
  endfunction()
  
  # Option 3: Conditional Instrumentation
  # Save the original PCL_ADD_TEST macro before overriding it
  # We need to include the targets cmake file first to get the original macro
  include(${PCL_SOURCE_DIR}/cmake/pcl_targets.cmake)
  
  # Macro to add test with instrumentation
  macro(PCL_ADD_TEST_WITH_INSTRUMENTATION name exename)
    # Parse arguments first
    set(options)
    set(oneValueArgs)
    set(multiValueArgs FILES ARGUMENTS LINK_WITH)
    cmake_parse_arguments(PCLTEST "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    # Call add_executable with the FILES argument
    add_executable(${exename} ${PCLTEST_FILES})
    if(NOT WIN32)
      set_target_properties(${exename} PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})
    endif()
    
    target_link_libraries(${exename} ${PCLTEST_LINK_WITH} ${CLANG_LIBRARIES})
    target_link_libraries(${exename} Threads::Threads ${ATOMIC_LIBRARY})
    if(PCLTEST_ARGUMENTS)
      set_target_properties(${exename} PROPERTIES VS_DEBUGGER_COMMAND_ARGUMENTS "${PCLTEST_ARGUMENTS}")
    endif()
    add_test(NAME ${name} COMMAND ${exename} ${PCLTEST_ARGUMENTS})
    set_property(TEST ${name} APPEND PROPERTY ENVIRONMENT "LD_LIBRARY_PATH=$ENV{LD_LIBRARY_PATH}:${CMAKE_BINARY_DIR}/lib")
    
    # Add instrumented version
    PCL_ADD_TEST_INSTRUMENTED(${exename})
  endmacro()
endif()

# Add test subdirectories after LLVM macros are defined
add_subdirectory(2d)
add_subdirectory(common)
add_subdirectory(features)
add_subdirectory(filters)
add_subdirectory(geometry)
add_subdirectory(gpu)
add_subdirectory(io)
add_subdirectory(kdtree)
add_subdirectory(keypoints)
add_subdirectory(ml)
add_subdirectory(people)
add_subdirectory(octree)
add_subdirectory(outofcore)
add_subdirectory(recognition)
add_subdirectory(registration)
add_subdirectory(search)
add_subdirectory(surface)
add_subdirectory(segmentation)
add_subdirectory(sample_consensus)
add_subdirectory(visualization)
