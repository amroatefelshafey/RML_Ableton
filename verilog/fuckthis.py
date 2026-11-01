from qkeras.utils import load_qmodel
import numpy as np

# Load your specific IDS classifier model
model = load_qmodel("models/ids_cnn1d_qat_best.h5")

with open("manual_weights.h", "w") as f:
    for layer_name in ['conv1', 'conv2', 'dense1', 'dense2']:
        layer = model.get_layer(layer_name)
        weights, biases = layer.get_weights()
        
        # Scale and cast to integers based on your fixed-point config
        # e.g., fixed<8,3> means 8 bits total, 3 integer bits -> 5 fractional bits (2^5 = 32)
        scale = 32 if layer_name in ['conv1', 'dense2'] else 2 # fixed<4,3> has 1 fractional bit
        
        w_int = np.round(weights * scale).flatten().astype(int)
        b_int = np.round(biases * scale).flatten().astype(int)
        
        f.write(f"const int8_t {layer_name}_w[] = {{{', '.join(map(str, w_int))}}};\n")
        f.write(f"const int8_t {layer_name}_b[] = {{{', '.join(map(str, b_int))}}};\n")
