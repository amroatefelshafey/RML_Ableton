#ifndef DEFINES_H_
#define DEFINES_H_

#include <sycl/ext/altera/ac_types/ac_fixed.hpp>
#include <sycl/ext/altera/ac_types/ac_int.hpp>
#include <sycl/ext/altera/fpga_extensions.hpp>
#include <sycl/sycl.hpp>

// Include nnet::array - a custom array-like struct, mainly used with io_stream
#include "nnet_utils/nnet_types.h"

// hls-fpga-machine-learning insert numbers

// hls-fpga-machine-learning insert layer-precision
typedef nnet::array<ac_fixed<16,6,true>, 4*1> input_t;
typedef ac_fixed<16,6,true> model_default_t;
typedef nnet::array<ac_fixed<29,14,true>, 16*1> conv1_result_t;
typedef nnet::array<ac_fixed<8,3,true>, 192*1> w2_t;
typedef nnet::array<ac_fixed<8,3,true>, 16*1> b2_t;
typedef nnet::array<ac_fixed<6,2,false,AC_RND_CONV,AC_SAT>, 16*1> layer3_t;
typedef ac_fixed<18,8,true> conv1_quantized_relu_table_t;
typedef nnet::array<ac_fixed<6,2,false,AC_RND_CONV,AC_SAT>, 16*1> layer4_t;
typedef nnet::array<ac_fixed<17,12,true>, 24*1> conv2_result_t;
typedef nnet::array<ac_fixed<4,3,true>, 1152*1> w5_t;
typedef nnet::array<ac_fixed<4,3,true>, 24*1> b5_t;
typedef nnet::array<ac_fixed<6,2,false,AC_RND_CONV,AC_SAT>, 24*1> layer6_t;
typedef ac_fixed<18,8,true> conv2_quantized_relu_table_t;
typedef nnet::array<ac_fixed<6,2,false,AC_RND_CONV,AC_SAT>, 120*1> layer7_t;
typedef nnet::array<ac_fixed<18,13,true>, 32*1> dense1_result_t;
typedef nnet::array<ac_fixed<4,3,true>, 8192> w8_t;
typedef nnet::array<ac_fixed<4,3,true>, 32*1> b8_t;
typedef ac_int<1, false> layer8_index;
typedef nnet::array<ac_fixed<6,2,false,AC_RND_CONV,AC_SAT>, 32*1> layer9_t;
typedef ac_fixed<18,8,true> dense1_quantized_relu_table_t;
typedef nnet::array<ac_fixed<20,11,true>, 8*1> dense2_result_t;
typedef nnet::array<ac_fixed<8,3,true>, 256*1> w10_t;
typedef nnet::array<ac_fixed<8,3,true>, 8*1> b10_t;
typedef ac_int<1, false> layer10_index;
typedef nnet::array<ac_fixed<16,6,true>, 8*1> result_t;
typedef ac_fixed<18,8,true> output_softmax_table_t;
typedef ac_fixed<18,8,true,AC_RND,AC_SAT> output_softmax_exp_table_t;
typedef ac_fixed<18,8,true,AC_RND,AC_SAT> output_softmax_inv_table_t;
typedef ac_fixed<18,8,true,AC_RND,AC_SAT> output_softmax_inv_inp_t;

#define DIV_ROUNDUP(n, d) ((n + d - 1) / d)
#define MIN(n, d) (n > d ? d : n)
#define MAX(n, d) (n < d ? d : n)

#endif
