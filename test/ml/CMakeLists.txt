set(SUBSYS_NAME tests_ml)
set(SUBSYS_DESC "Point cloud library ml module unit tests")
PCL_SET_TEST_DEPENDENCIES(SUBSYS_DEPS ml)

PCL_SUBSYS_OPTION(build "${SUBSYS_NAME}" "${SUBSYS_DESC}" ON)
PCL_SUBSYS_DEPEND(build NAME ${SUBSYS_NAME} DEPS ${SUBSYS_DEPS} OPT_DEPS ${OPT_DEPS})

if(NOT build)
  return()
endif()

if(PCL_ENABLE_LLVM_IR)
  PCL_ADD_TEST_WITH_INSTRUMENTATION(ml_kmeans test_ml_kmeans FILES test_kmeans.cpp LINK_WITH pcl_gtest pcl_common pcl_ml)
else()
  PCL_ADD_TEST(ml_kmeans test_ml_kmeans FILES test_kmeans.cpp LINK_WITH pcl_gtest pcl_common pcl_ml)
endif()
