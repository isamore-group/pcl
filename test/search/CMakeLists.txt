set(SUBSYS_NAME tests_search)
set(SUBSYS_DESC "Point cloud library search module unit tests")
PCL_SET_TEST_DEPENDENCIES(SUBSYS_DEPS search)
set(OPT_DEPS io)

PCL_SUBSYS_OPTION(build "${SUBSYS_NAME}" "${SUBSYS_DESC}" ON)
PCL_SUBSYS_DEPEND(build NAME ${SUBSYS_NAME} DEPS ${SUBSYS_DEPS} OPT_DEPS ${OPT_DEPS})

if(NOT build)
  return()
endif()

if(PCL_ENABLE_LLVM_IR)
  PCL_ADD_TEST_WITH_INSTRUMENTATION(kdtree_search test_kdtree_search
             FILES test_kdtree.cpp
             LINK_WITH pcl_gtest pcl_search pcl_kdtree)
else()
  PCL_ADD_TEST(kdtree_search test_kdtree_search
             FILES test_kdtree.cpp
             LINK_WITH pcl_gtest pcl_search pcl_kdtree)
endif()

if(PCL_ENABLE_LLVM_IR)
  PCL_ADD_TEST_WITH_INSTRUMENTATION(flann_search test_flann_search
             FILES test_flann_search.cpp
             LINK_WITH pcl_gtest pcl_search pcl_kdtree)
else()
  PCL_ADD_TEST(flann_search test_flann_search
             FILES test_flann_search.cpp
             LINK_WITH pcl_gtest pcl_search pcl_kdtree)
endif()

if(PCL_ENABLE_LLVM_IR)
  PCL_ADD_TEST_WITH_INSTRUMENTATION(organized_neighbor test_organized_search
             FILES test_organized.cpp
             LINK_WITH pcl_gtest pcl_search pcl_kdtree)
else()
  PCL_ADD_TEST(organized_neighbor test_organized_search
             FILES test_organized.cpp
             LINK_WITH pcl_gtest pcl_search pcl_kdtree)
endif()

if(PCL_ENABLE_LLVM_IR)
  PCL_ADD_TEST_WITH_INSTRUMENTATION(octree_search test_octree_search
             FILES test_octree.cpp
             LINK_WITH pcl_gtest pcl_search pcl_octree pcl_common)
else()
  PCL_ADD_TEST(octree_search test_octree_search
             FILES test_octree.cpp
             LINK_WITH pcl_gtest pcl_search pcl_octree pcl_common)
endif()

if(BUILD_io)
    if(PCL_ENABLE_LLVM_IR)
    PCL_ADD_TEST_WITH_INSTRUMENTATION(search test_search
               FILES test_search.cpp
               LINK_WITH pcl_gtest pcl_search pcl_io pcl_kdtree
               ARGUMENTS "${PCL_SOURCE_DIR}/test/table_scene_mug_stereo_textured.pcd")
  else()
    PCL_ADD_TEST(search test_search
               FILES test_search.cpp
               LINK_WITH pcl_gtest pcl_search pcl_io pcl_kdtree
               ARGUMENTS "${PCL_SOURCE_DIR}/test/table_scene_mug_stereo_textured.pcd")
  endif()

    if(PCL_ENABLE_LLVM_IR)
    PCL_ADD_TEST_WITH_INSTRUMENTATION(organized_index test_organized_index
          FILES test_organized_index.cpp
          LINK_WITH pcl_gtest pcl_search pcl_common pcl_io
          ARGUMENTS "${PCL_SOURCE_DIR}/test/office1.pcd")
  else()
    PCL_ADD_TEST(organized_index test_organized_index
          FILES test_organized_index.cpp
          LINK_WITH pcl_gtest pcl_search pcl_common pcl_io
          ARGUMENTS "${PCL_SOURCE_DIR}/test/office1.pcd")
  endif()
endif()
