#!/usr/bin/env python
# %%
import bisect
import random
from functools import lru_cache


def is_bits(s, l=None):
    return isinstance(s, str) and len(s) and all(c in '01' for c in s) and (l is None or len(s) == l)


@lru_cache(maxsize=None)
def e5tof(s):
    assert is_bits(s, 8), f"s={repr(s)}"
    sig, exp, man = s[0], s[1:6], s[6:]
    assert is_bits(sig, 1), f"sig={repr(sig)}"
    assert is_bits(exp, 5), f"exp={repr(exp)}"
    assert is_bits(man, 2), f"man={repr(man)}"

    sign = -1 if sig == '1' else 1

    if exp == '11111':
        if man == '00':
            return sign * float('inf')
        return float('nan')
    
    if exp == '00000':
        frac = int(man, 2) / (1 << len(man))
        pow = 2 ** -14
    else:
        frac = 1.0 + int(man, 2) / (1 << len(man))
        pow = 2 ** (int(exp, 2) - 15)
    return sign * frac * pow

# Build the lookup map
fe5 = []
fe5map = {}
for i in range(-123, 124):
    s = f"0{i:07b}" if i >= 0 else f"1{-i:07b}"
    f = e5tof(s)
    assert f == f and f != float('inf'), f"{s} -> {f}"
    fe5.append((f, s))
    fe5map[f] = s

@lru_cache(maxsize=None)
def ftoe5(f):
    assert isinstance(f, float), f"f={repr(f)}"
    # Zeroth check for NaN
    if f != f:
        return '01111101'
    # First check for bounds
    if f > fe5[-1][0]:
        return '01111100'
    if f < fe5[0][0]:
        return '11111100'
    # Then check for exact matches
    if f in fe5map:
        return fe5map[f]
    # Binary search in the fe5 table, and check both sides
    # to make sure we have the nearest float.
    i = bisect.bisect_left(fe5, (f, ''))
    assert 0 < i < len(fe5), f"i={i}, f={f}"
    higher = fe5[i][0]
    lower = fe5[i - 1][0]
    assert lower < f < higher, f"lower={lower}, f={f}, higher={higher}, i={i}"
    # If equal distance, return the even one
    if f - lower == higher - f:
        if int(fe5[i][1][-1]) == 0:
            return fe5[i][1]
        return fe5[i - 1][1]
    # Otherwise return the nearest one
    if f - lower < higher - f:
        return fe5[i - 1][1]
    return fe5[i][1]


# Test all of them
for i in range(256):
    e5tof(f"{i:08b}")
# Test random floats
for _ in range(1000):
    f = random.uniform(-60000., 60000.)
    ftoe5(f)