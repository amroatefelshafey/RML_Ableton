#ifndef PARAMETERS_H_
#define PARAMETERS_H_

#include "defines.h"

#include "nnet_utils/nnet_code_gen.h"
#include "nnet_utils/nnet_helpers.h"

// hls-fpga-machine-learning insert includes
#include "nnet_utils/nnet_activation.h"
#include "nnet_utils/nnet_activation_stream.h"
#include "nnet_utils/nnet_conv1d.h"
#include "nnet_utils/nnet_conv1d_stream.h"
#include "nnet_utils/nnet_dense.h"
#include "nnet_utils/nnet_dense_stream.h"
#include "nnet_utils/nnet_pooling.h"
#include "nnet_utils/nnet_pooling_stream.h"
#include "nnet_utils/nnet_stream.h"

// hls-fpga-machine-learning insert layer-config
struct config2_mult : nnet::dense_config {
    static const unsigned n_in = 12;
    static const unsigned n_out = 16;

    static const unsigned rf_pad = 0;
    static const unsigned bf_pad = 0;

    static const unsigned reuse_factor = 2;
    static const unsigned reuse_factor_rounded = reuse_factor + rf_pad;
    static const unsigned block_factor = DIV_ROUNDUP(n_in*n_out, reuse_factor);
    static const unsigned block_factor_rounded = block_factor + bf_pad;
    static const unsigned multiplier_factor = MIN(n_in, reuse_factor);
    static const unsigned multiplier_limit = DIV_ROUNDUP(n_in*n_out, multiplier_factor);
    static const unsigned multiplier_scale = multiplier_limit/n_out;

    typedef model_default_t accum_t;
    typedef b2_t bias_t;
    typedef w2_t weight_t;

    template<class x_T, class y_T>
    using product = nnet::product::mult<x_T, y_T>;
};

struct config2 : nnet::conv1d_config {
    static const unsigned in_width = 16;
    static const unsigned n_chan = 4;

    static const unsigned filt_width = 3;
    static const unsigned impl_filt_width = 3;
    static const unsigned kernel_size = filt_width;

    static const unsigned n_filt = 16;
    static const unsigned out_width = 14;

    static const unsigned pad_left = 0;
    static const unsigned pad_right = 0;
    static const unsigned stride_width = 1;
    static const unsigned dilation = 1;

    static const unsigned reuse_factor = 2;
    static const unsigned parallelization_factor = 1;
    static const bool store_weights_in_bram = false;

    static const nnet::conv1d_implementation implementation = nnet::conv1d_implementation::im2col;

    typedef model_default_t accum_t;
    typedef b2_t bias_t;
    typedef w2_t weight_t;
    typedef config2_mult mult_config;
};

struct relu_config3 : nnet::activ_config {
    static constexpr unsigned n_in = 224;
    static constexpr unsigned table_size = 1024;
    static constexpr unsigned io_type = nnet::io_stream;
    static constexpr unsigned reuse_factor = 1;
    typedef conv1_quantized_relu_table_t table_t;
};

struct config4 : nnet::pooling1d_config {
    static const unsigned stride_width = 2;
    static const unsigned pool_width = 2;

    static const unsigned n_in = 14;
    static const unsigned n_out = 7;
    static const unsigned filt_width = 2;

    static const unsigned n_filt = 16;
    static const unsigned n_chan = 16;

    static const unsigned in_width = 14;

    static const unsigned pad_left = 0;
    static const unsigned pad_right = 0;
    static const bool count_pad = false;

    static const nnet::Pool_Op pool_op = nnet::Max;
    typedef model_default_t accum_t;
};

struct config5_mult : nnet::dense_config {
    static const unsigned n_in = 48;
    static const unsigned n_out = 24;

    static const unsigned rf_pad = 0;
    static const unsigned bf_pad = 0;

    static const unsigned reuse_factor = 4;
    static const unsigned reuse_factor_rounded = reuse_factor + rf_pad;
    static const unsigned block_factor = DIV_ROUNDUP(n_in*n_out, reuse_factor);
    static const unsigned block_factor_rounded = block_factor + bf_pad;
    static const unsigned multiplier_factor = MIN(n_in, reuse_factor);
    static const unsigned multiplier_limit = DIV_ROUNDUP(n_in*n_out, multiplier_factor);
    static const unsigned multiplier_scale = multiplier_limit/n_out;

    typedef model_default_t accum_t;
    typedef b5_t bias_t;
    typedef w5_t weight_t;

    template<class x_T, class y_T>
    using product = nnet::product::mult<x_T, y_T>;
};

struct config5 : nnet::conv1d_config {
    static const unsigned in_width = 7;
    static const unsigned n_chan = 16;

    static const unsigned filt_width = 3;
    static const unsigned impl_filt_width = 3;
    static const unsigned kernel_size = filt_width;

    static const unsigned n_filt = 24;
    static const unsigned out_width = 5;

    static const unsigned pad_left = 0;
    static const unsigned pad_right = 0;
    static const unsigned stride_width = 1;
    static const unsigned dilation = 1;

    static const unsigned reuse_factor = 4;
    static const unsigned parallelization_factor = 1;
    static const bool store_weights_in_bram = false;

    static const nnet::conv1d_implementation implementation = nnet::conv1d_implementation::im2col;

    typedef model_default_t accum_t;
    typedef b5_t bias_t;
    typedef w5_t weight_t;
    typedef config5_mult mult_config;
};

struct relu_config6 : nnet::activ_config {
    static constexpr unsigned n_in = 120;
    static constexpr unsigned table_size = 1024;
    static constexpr unsigned io_type = nnet::io_stream;
    static constexpr unsigned reuse_factor = 1;
    typedef conv2_quantized_relu_table_t table_t;
};

struct config8 : nnet::dense_config {
    static constexpr unsigned n_in = 120;
    static constexpr unsigned n_out = 32;
    static constexpr unsigned io_type = nnet::io_stream;
    static constexpr unsigned n_zeros = 2679;
    static constexpr unsigned n_nonzeros = 1161;
    static constexpr bool store_weights_in_bram = false;

    static constexpr unsigned rf_pad = 12;
    static constexpr unsigned bf_pad = 64;

    static constexpr unsigned reuse_factor = 20;
    static constexpr unsigned compressed_block_factor = DIV_ROUNDUP(n_nonzeros, reuse_factor);
    static constexpr unsigned reuse_factor_rounded = reuse_factor + rf_pad;
    static constexpr unsigned block_factor = DIV_ROUNDUP(n_in*n_out, reuse_factor);
    static constexpr unsigned block_factor_rounded = block_factor + bf_pad;
    static constexpr unsigned multiplier_factor = MIN(n_in, reuse_factor);
    static constexpr unsigned multiplier_limit = DIV_ROUNDUP(n_in*n_out, multiplier_factor);
    static constexpr unsigned multiplier_scale = multiplier_limit/n_out;

    typedef model_default_t accum_t;
    typedef b8_t bias_t;
    typedef w8_t weight_t;
    typedef layer8_index index_t;

    template<class x_T, class y_T>
    using product = nnet::product::mult<x_T, y_T>;
};

struct relu_config9 : nnet::activ_config {
    static constexpr unsigned n_in = 32;
    static constexpr unsigned table_size = 1024;
    static constexpr unsigned io_type = nnet::io_stream;
    static constexpr unsigned reuse_factor = 1;
    typedef dense1_quantized_relu_table_t table_t;
};

struct config10 : nnet::dense_config {
    static constexpr unsigned n_in = 32;
    static constexpr unsigned n_out = 8;
    static constexpr unsigned io_type = nnet::io_stream;
    static constexpr unsigned n_zeros = 5;
    static constexpr unsigned n_nonzeros = 251;
    static constexpr bool store_weights_in_bram = false;

    static constexpr unsigned rf_pad = 0;
    static constexpr unsigned bf_pad = 0;

    static constexpr unsigned reuse_factor = 4;
    static constexpr unsigned compressed_block_factor = DIV_ROUNDUP(n_nonzeros, reuse_factor);
    static constexpr unsigned reuse_factor_rounded = reuse_factor + rf_pad;
    static constexpr unsigned block_factor = DIV_ROUNDUP(n_in*n_out, reuse_factor);
    static constexpr unsigned block_factor_rounded = block_factor + bf_pad;
    static constexpr unsigned multiplier_factor = MIN(n_in, reuse_factor);
    static constexpr unsigned multiplier_limit = DIV_ROUNDUP(n_in*n_out, multiplier_factor);
    static constexpr unsigned multiplier_scale = multiplier_limit/n_out;

    typedef model_default_t accum_t;
    typedef b10_t bias_t;
    typedef w10_t weight_t;
    typedef layer10_index index_t;

    template<class x_T, class y_T>
    using product = nnet::product::mult<x_T, y_T>;
};

struct softmax_config12 : nnet::activ_config {
    static constexpr unsigned n_in = 8;
    static constexpr unsigned table_size = 1024;
    static constexpr unsigned io_type = nnet::io_stream;
    static constexpr unsigned reuse_factor = 1;
    static constexpr nnet::softmax_implementation implementation = nnet::softmax_implementation::stable;
    typedef output_softmax_exp_table_t exp_table_t;
    typedef output_softmax_inv_table_t inv_table_t;
};


#endif
