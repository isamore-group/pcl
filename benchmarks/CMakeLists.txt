set(SUBSYS_NAME benchmarks)
set(SUBSYS_DESC "Point cloud library benchmarks")
set(SUBSYS_DEPS common filters features search kdtree io)

PCL_SUBSYS_OPTION(build "${SUBSYS_NAME}" "${SUBSYS_DESC}" OFF)
PCL_SUBSYS_DEPEND(build NAME ${SUBSYS_NAME} DEPS ${SUBSYS_DEPS})
if(NOT build)
  return()
endif()

find_package(benchmark REQUIRED)
get_target_property(BenchmarkBuildType benchmark::benchmark TYPE)

add_custom_target(run_benchmarks)

PCL_ADD_BENCHMARK(features_normal_3d FILES features/normal_3d.cpp
                  LINK_WITH pcl_io pcl_search pcl_features
                  ARGUMENTS "${PCL_SOURCE_DIR}/test/table_scene_mug_stereo_textured.pcd"
                            "${PCL_SOURCE_DIR}/test/milk_cartoon_all_small_clorox.pcd")

PCL_ADD_BENCHMARK(filters_voxel_grid FILES filters/voxel_grid.cpp
                  LINK_WITH pcl_io pcl_filters
                  ARGUMENTS "${PCL_SOURCE_DIR}/test/table_scene_mug_stereo_textured.pcd"
                            "${PCL_SOURCE_DIR}/test/milk_cartoon_all_small_clorox.pcd")

PCL_ADD_BENCHMARK(filters_radius_outlier_removal FILES filters/radius_outlier_removal.cpp
                  LINK_WITH pcl_io pcl_filters
                  ARGUMENTS "${PCL_SOURCE_DIR}/test/table_scene_mug_stereo_textured.pcd"
                            "${PCL_SOURCE_DIR}/test/milk_cartoon_all_small_clorox.pcd")

PCL_ADD_BENCHMARK(search_radius_search FILES search/radius_search.cpp
                  LINK_WITH pcl_io pcl_search
                  ARGUMENTS "${PCL_SOURCE_DIR}/test/table_scene_mug_stereo_textured.pcd"
                            "${PCL_SOURCE_DIR}/test/milk_cartoon_all_small_clorox.pcd")

# ISAMORE LLVM IR generation for benchmarks
if(PCL_ENABLE_LLVM_IR)
  # Function to add LLVM IR generation for a benchmark
  function(PCL_ADD_BENCHMARK_LLVM_IR name)
    # Extract just the benchmark name without "pcl_" prefix
    string(REPLACE "pcl_" "" bench_name ${name})
    
    # Find the source file
    set(bench_src "")
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/features/${bench_name}.cpp")
      set(bench_src "${CMAKE_CURRENT_SOURCE_DIR}/features/${bench_name}.cpp")
    elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/filters/${bench_name}.cpp")
      set(bench_src "${CMAKE_CURRENT_SOURCE_DIR}/filters/${bench_name}.cpp")
    elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/search/${bench_name}.cpp")
      set(bench_src "${CMAKE_CURRENT_SOURCE_DIR}/search/${bench_name}.cpp")
    endif()
    
    if(NOT bench_src)
      return()
    endif()
    
    # Create LLVM directory for benchmarks
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/benchmarks/llvm")
    
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
    # Add benchmark includes
    set(include_dirs "${include_dirs} -I${benchmark_INCLUDE_DIRS}")
    
    # Add definitions
    set(definitions "-DPCL_NO_PRECOMPILE")
    
    # Generate LLVM IR
    add_custom_command(
      OUTPUT ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}.ll
      COMMAND ${CMAKE_BINARY_DIR}/compile_pcl_to_ll.sh
              ${bench_src}
              ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}.ll
              "${include_dirs}"
              "${definitions}"
      DEPENDS ${bench_src} ${CMAKE_BINARY_DIR}/compile_pcl_to_ll.sh
      COMMENT "Generating LLVM IR for benchmark ${bench_name}"
    )
    
    # Instrument the benchmark
    add_custom_command(
      OUTPUT ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}_instrumented.ll
      COMMAND ${OPT} -load-pass-plugin="${PASS_PATH}" -passes=bb_instrument
              ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}.ll
              -o ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}_instrumented.ll 2>/dev/null || touch ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}_instrumented.ll
      DEPENDS ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}.ll
      COMMENT "Instrumenting LLVM IR for benchmark ${bench_name}"
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
        OUTPUT ${CMAKE_BINARY_DIR}/benchmarks/${bench_name}_instrumented
        COMMAND ${LLVM_LINK} ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}_instrumented.ll ${module_bcs}
                -o ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}_linked.bc
        COMMAND ${CLANG} ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}_linked.bc
                -o ${CMAKE_BINARY_DIR}/benchmarks/${bench_name}_instrumented
                -lm -lpthread -lboost_system -lboost_filesystem -lboost_thread -lboost_date_time -lboost_iostreams -lboost_chrono -lboost_atomic -lboost_regex
                -lbenchmark -L${PCL_BINARY_DIR}/lib
        DEPENDS ${CMAKE_BINARY_DIR}/benchmarks/llvm/${bench_name}_instrumented.ll ${module_bcs}
        COMMENT "Building instrumented executable: ${bench_name}_instrumented"
      )
      
      # Copy to __binary for profiling
      add_custom_command(
        OUTPUT ${CMAKE_BINARY_DIR}/__binary/${bench_name}_instrumented
        COMMAND ${CMAKE_COMMAND} -E copy
                ${CMAKE_BINARY_DIR}/benchmarks/${bench_name}_instrumented
                ${CMAKE_BINARY_DIR}/__binary/${bench_name}_instrumented
        DEPENDS ${CMAKE_BINARY_DIR}/benchmarks/${bench_name}_instrumented
        COMMENT "Copying instrumented benchmark to __binary"
      )
      
      add_custom_target(${bench_name}_instrumented_exe ALL
        DEPENDS ${CMAKE_BINARY_DIR}/__binary/${bench_name}_instrumented
      )
    endif()
  endfunction()
endif()

