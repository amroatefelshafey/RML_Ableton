#ifndef MYPROJECT_H_
#define MYPROJECT_H_

#include "defines.h"

// This file defines the interface to the kernel

// currently this is fixed
using PipeProps = decltype(sycl::ext::oneapi::experimental::properties(sycl::ext::altera::experimental::ready_latency<0>));

// Need to declare the input and output pipes

// hls-fpga-machine-learning insert inputs
class Input1PipeID;
using Input1Pipe = sycl::ext::altera::experimental::pipe<Input1PipeID, input_t, 0, PipeProps>;
// hls-fpga-machine-learning insert outputs
class Layer12OutPipeID;
using Layer12OutPipe = sycl::ext::altera::experimental::pipe<Layer12OutPipeID, result_t, 0, PipeProps>;

class MyprojectID;

struct Myproject {

    // kernel property method to config invocation interface
    auto get(sycl::ext::oneapi::experimental::properties_tag) {
        return sycl::ext::oneapi::experimental::properties{sycl::ext::altera::experimental::streaming_interface<>,
                                                           sycl::ext::altera::experimental::pipelined<>};
    }

    SYCL_EXTERNAL void operator()() const;
};

#endif
