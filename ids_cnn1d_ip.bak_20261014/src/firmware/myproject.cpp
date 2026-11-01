#include "myproject.h"
#include "parameters.h"
#include <sycl/ext/altera/experimental/task_sequence.hpp>

// hls-fpga-machine-learning insert weights
#include "weights/w2.h"
#include "weights/b2.h"
#include "weights/w5.h"
#include "weights/b5.h"
#include "weights/w8.h"
#include "weights/b8.h"
#include "weights/w10.h"
#include "weights/b10.h"

// The inter-task pipes need to be declared in the global scope
// hls-fpga-machine-learning insert inter-task pipes
class Layer2OutPipeID;
using Layer2OutPipe = sycl::ext::altera::experimental::pipe<Layer2OutPipeID, conv1_result_t, 14>;
class Layer3OutPipeID;
using Layer3OutPipe = sycl::ext::altera::experimental::pipe<Layer3OutPipeID, layer3_t, 14>;
class Layer4OutPipeID;
using Layer4OutPipe = sycl::ext::altera::experimental::pipe<Layer4OutPipeID, layer4_t, 7>;
class Layer5OutPipeID;
using Layer5OutPipe = sycl::ext::altera::experimental::pipe<Layer5OutPipeID, conv2_result_t, 5>;
class Layer6OutPipeID;
using Layer6OutPipe = sycl::ext::altera::experimental::pipe<Layer6OutPipeID, layer6_t, 5>;
class Layer7OutPipeID;
using Layer7OutPipe = sycl::ext::altera::experimental::pipe<Layer7OutPipeID, layer7_t, 1>;
class Layer8OutPipeID;
using Layer8OutPipe = sycl::ext::altera::experimental::pipe<Layer8OutPipeID, dense1_result_t, 1>;
class Layer9OutPipeID;
using Layer9OutPipe = sycl::ext::altera::experimental::pipe<Layer9OutPipeID, layer9_t, 1>;
class Layer10OutPipeID;
using Layer10OutPipe = sycl::ext::altera::experimental::pipe<Layer10OutPipeID, dense2_result_t, 1>;

using sycl::ext::altera::experimental::task_sequence;

void Myproject::operator()() const {
    // ****************************************
    // NETWORK INSTANTIATION
    // ****************************************

    // hls-fpga-machine-learning read in

    // hls-fpga-machine-learning declare task sequences
    task_sequence<nnet::conv_1d_cl_stream<Input1Pipe, Layer2OutPipe, config2>> conv1;
    task_sequence<nnet::relu_stream<Layer2OutPipe, Layer3OutPipe, relu_config3>> conv1_quantized_relu;
    task_sequence<nnet::pooling1d_cl_stream<Layer3OutPipe, Layer4OutPipe, config4>>(pool1);
    task_sequence<nnet::conv_1d_cl_stream<Layer4OutPipe, Layer5OutPipe, config5>> conv2;
    task_sequence<nnet::relu_stream<Layer5OutPipe, Layer6OutPipe, relu_config6>> conv2_quantized_relu;
    task_sequence<nnet::repack_stream<Layer6OutPipe, Layer7OutPipe, 120>> flatten;
    task_sequence<nnet::dense_resource_stream<Layer7OutPipe, Layer8OutPipe, config8>> dense1;
    task_sequence<nnet::relu_stream<Layer8OutPipe, Layer9OutPipe, relu_config9>> dense1_quantized_relu;
    task_sequence<nnet::dense_resource_stream<Layer9OutPipe, Layer10OutPipe, config10>> dense2;
    task_sequence<nnet::softmax_stream<Layer10OutPipe, Layer12OutPipe, softmax_config12>> output_softmax;

    // hls-fpga-machine-learning insert layers

    conv1.async(w2, b2);
    conv1_quantized_relu.async();
    pool1.async();
    conv2.async(w5, b5);
    conv2_quantized_relu.async();
    flatten.async();
    dense1.async(w8, b8);
    dense1_quantized_relu.async();
    dense2.async(w10, b10);
    output_softmax.async();

    // hls-fpga-machine-learning return
}
