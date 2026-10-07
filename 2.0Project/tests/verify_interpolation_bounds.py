"""Exhaustive proof of the exact 8-bit bilinear-channel range.

This checks every endpoint/weight triplet against mathematical floor
division, independently of the RTL bit slices. RTL resampling is covered
by the scaler image/endpoint/pacing regressions.
"""
import numpy as np

base=np.arange(256,dtype=np.int32)[:,None]
current=np.arange(256,dtype=np.int32)[None,:]
checks=0
for weight in range(256):
    product=(current-base)*weight
    reference=base+np.floor_divide(product,256)
    bounded_sum=(base+((product >> 8) & 255)) & 255
    assert np.all((reference>=0) & (reference<=255))
    assert np.array_equal(reference,bounded_sum)
    checks+=reference.size
print(f'PASS exhaustive bounded interpolation: {checks} endpoint/weight combinations')
