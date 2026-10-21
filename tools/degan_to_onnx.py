# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
#
# Convertit les poids Keras de DE-GAN (https://github.com/dali92002/DE-GAN, GPL-3.0) en ONNX 256x256
# pour Kyokasho, sans TensorFlow : lecture du .h5 (h5py), graphe U-Net reecrit avec onnx.
# Usage : python3 degan_to_onnx.py binarization_generator_weights.h5 degan-binarize.onnx
# Dependances : pip install h5py onnx numpy
import sys, h5py, numpy as np, onnx
from onnx import helper, TensorProto, numpy_helper
src, dst, fp16 = sys.argv[1], sys.argv[2], False  # fp32 : CoreML (NeuralNetwork) refuse le fp16 ici
f = h5py.File(src, 'r')
def w(name):
    g = f[name]; ws = [x.decode() if isinstance(x, bytes) else x for x in g.attrs['weight_names']]
    return g[ws[0]][()], g[ws[1]][()]
nodes, inits = [], []
dt = np.float16 if fp16 else np.float32
def conv(x, name, act='relu'):
    k, b = w(name)
    kh = k.shape[0]
    inits.append(numpy_helper.from_array(k.transpose(3, 2, 0, 1).astype(dt), name + '_W'))
    inits.append(numpy_helper.from_array(b.astype(dt), name + '_B'))
    pads = [1, 1, 1, 1] if kh == 3 else ([0, 0, 1, 1] if kh == 2 else [0, 0, 0, 0])
    nodes.append(helper.make_node('Conv', [x, name + '_W', name + '_B'], [name + '_c'], pads=pads))
    out = name + '_o'
    nodes.append(helper.make_node('Relu' if act == 'relu' else 'Sigmoid', [name + '_c'], [out]))
    return out
def pool(x, n):
    nodes.append(helper.make_node('MaxPool', [x], [n], kernel_shape=[2, 2], strides=[2, 2], pads=[0, 0, 0, 0])); return n
inits.append(numpy_helper.from_array(np.array([1, 1, 2, 2], np.float32), 'scales'))
def up(x, n):
    nodes.append(helper.make_node('Resize', [x, '', 'scales'], [n], mode='nearest', nearest_mode='floor',
                                  coordinate_transformation_mode='asymmetric')); return n
def cat(a, b, n):
    nodes.append(helper.make_node('Concat', [a, b], [n], axis=1)); return n
x = 'image'
if fp16:
    nodes.append(helper.make_node('Cast', ['image'], ['image16'], to=TensorProto.FLOAT16)); x = 'image16'
c = lambda i: 'conv2d' if i == 0 else f'conv2d_{i}'
c1 = conv(conv(x, c(0)), c(1)); p = pool(c1, 'p1')
c2 = conv(conv(p, c(2)), c(3)); p = pool(c2, 'p2')
c3 = conv(conv(p, c(4)), c(5)); p = pool(c3, 'p3')
c4 = conv(conv(p, c(6)), c(7)); p = pool(c4, 'p4')
c5 = conv(conv(p, c(8)), c(9))
u = conv(up(c5, 'u6'), c(10)); m = conv(conv(cat(c4, u, 'm6'), c(11)), c(12))
u = conv(up(m, 'u7'), c(13)); m = conv(conv(cat(c3, u, 'm7'), c(14)), c(15))
u = conv(up(m, 'u8'), c(16)); m = conv(conv(cat(c2, u, 'm8'), c(17)), c(18))
u = conv(up(m, 'u9'), c(19)); m = conv(conv(conv(cat(c1, u, 'm9'), c(20)), c(21)), c(22))
out = conv(m, c(23), act='sigmoid')
if fp16:
    nodes.append(helper.make_node('Cast', [out], ['enhanced'], to=TensorProto.FLOAT))
else:
    nodes.append(helper.make_node('Identity', [out], ['enhanced']))
g = helper.make_graph(nodes, 'degan', [helper.make_tensor_value_info('image', TensorProto.FLOAT, [1, 1, 256, 256])],
                      [helper.make_tensor_value_info('enhanced', TensorProto.FLOAT, [1, 1, 256, 256])], inits)
m = helper.make_model(g, opset_imports=[helper.make_opsetid('', 17)]); m.ir_version = 8
onnx.checker.check_model(m); onnx.save(m, dst); print('ok', dst)
