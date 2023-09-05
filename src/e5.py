#!/usr/bin/env python
# %%
import bisect
import random
from dataclasses import dataclass
from functools import lru_cache
from itertools import product


def is_bin(s, l=None):
    return isinstance(s, str) and len(s) and all(c in '01' for c in s) and (l is None or len(s) == l)


def is_hex(s, l=None):
    return isinstance(s, str) and len(s) and all(c in '0123456789abcdef' for c in s.lower()) and (l is None or len(s) == l)


@dataclass
class Float:
    sig: str
    exp: str
    man: str

    @property
    def f(self):
        assert is_bin(self.sig, 1), f"sig={repr(self.sig)}"
        assert is_bin(self.exp, self.e_l), f"exp={repr(self.exp)}"
        assert is_bin(self.man, self.m_l), f"man={repr(self.man)}"
        sig = -1 if self.sig == '1' else 1
        exp = int(self.exp, 2) - 2 ** (self.e_l - 1) + 1
        man = int(self.man, 2) / (2 ** self.m_l)
        assert 0 <= man < 1, f"man={repr(man)}"
        if self.e_l == 5:
            if self.exp == '1' * self.e_l:
                return float('nan') if man else sig * float('inf')
        else:  # Special case for E4M3
            if (self.exp == '1' * self.e_l) and (self.man == '1' * self.m_l):
                return float('nan')
        if int(self.exp) == 0:
            return sig * (2 ** (exp + 1)) * man
        return sig * (2 ** exp) * (1.0 + man)

    @property
    def b(self):
        s = self.sig + self.exp + self.man
        assert is_bin(s, 1 + self.e_l + self.m_l), f"s={repr(s)}"
        return s
    
    @property
    def h(self):
        size = (1 + self.e_l + self.m_l) // 4
        s = f"{int(self.b, 2):0{size}x}"
        assert is_hex(s, size), f"s={repr(s)}"
        return s

    @classmethod
    def fromh(cls, h):
        assert is_hex(h, (1 + cls.e_l + cls.m_l) // 4), f"h={repr(h)}"
        return cls.fromb(f"{int(h, 16):0{1 + cls.e_l + cls.m_l}b}")

    @classmethod
    def fromf(cls, f, verbose=False):
        assert isinstance(f, float), f"f={repr(f)}"
        sig = '1' if f < 0 else '0'
        if f != f:  # NaN
            return cls('0', '1' * cls.e_l, '1' * cls.m_l)
        if cls.e_l == 5:  # Normal case
            if abs(f) > cls.MAX: # Inf
                return cls(sig, '1' * cls.e_l, '0' * cls.m_l)
        else:  # Special case for E4M3
            if abs(f) >= cls.MAX:  # Saturate to MAX
                return cls(sig, '1' * cls.e_l, '1' * (cls.m_l - 1) + '0')
        if abs(f) <= cls.MIN / 2:  # Zero
            return cls('0', '0' * cls.e_l, '0' * cls.m_l)
        if abs(f) <= cls.MIN:  # Min
            return cls(sig, '0' * cls.e_l, '0' * (cls.m_l - 1) + '1')
        # Compare bit by bit
        val = sig
        size = cls.e_l + cls.m_l
        for i in range(1, 1 + size):
            assert len(val) == i
            low = val + '0' + '1' * (size - i)
            high = val + '1' + '0' * (size - i)
            low_diff = abs(f - cls.fromb(low).f)
            high_diff = abs(f - cls.fromb(high).f)
            if verbose:
                print(f"i={i} val={val} low={low}, high={high}")
                print(f"low_diff={low_diff}, high_diff={high_diff}")
            if low_diff == high_diff:
                val = val + ('0' if i == size else '1')
            elif (low_diff < high_diff) or (high_diff != high_diff):
                val = val + '0'
            else:
                val = val + '1'
        return cls.fromb(val)


@dataclass
class FP16(Float):
    e_l: int = 5
    m_l: int = 10
    MAX: float = 65504.
    MIN: float = 2**-24

    @classmethod
    def fromb(cls, b):
        assert is_bin(b, 16), f"b={repr(b)}"
        return cls(b[0], b[1:6], b[6:])


@dataclass
class E5M2(Float):
    e_l: int = 5
    m_l: int = 2
    MAX: float = 57344.
    MIN: float = 2 ** -16

    @classmethod
    def fromb(cls, b):
        assert is_bin(b, 8), f"b={repr(b)}"
        return cls(b[0], b[1:6], b[6:])


@dataclass
class E4M3(Float):
    e_l: int = 4
    m_l: int = 3
    MAX: float = 448.
    MIN: float = 2 ** -9

    @classmethod
    def fromb(cls, b):
        assert is_bin(b, 8), f"b={repr(b)}"
        return cls(b[0], b[1:5], b[5:])


# Hard-coded NaN/Inf/Max/Min values
assert FP16.fromf(float('nan')).h == '7fff'
assert FP16.fromf(float('inf')).h == '7c00'
assert FP16.fromh('0001').f == FP16.MIN
assert FP16.fromh('7bff').f == FP16.MAX
assert E5M2.fromf(float('nan')).h == '7f'
assert E5M2.fromf(float('inf')).h == '7c'
assert E5M2.fromh('7b').f == E5M2.MAX
assert E5M2.fromh('01').f == E5M2.MIN
assert E4M3.fromf(float('nan')).h == '7f'
assert E4M3.fromf(float('inf')).h == '7e'  # Note this is MAX value
assert E4M3.fromh('7e').f == E4M3.MAX
assert E4M3.fromh('01').f == E4M3.MIN

suffixes = ['00', '01', '7e', '7f', '80', '81', 'fe', 'ff']
val8s = [f"{i:02x}" for i in range(256)]
val16s = [i+j for (i, j) in product(val8s, suffixes)]
for cls, vals in [(E5M2, val8s), (E4M3, val8s), (FP16, val16s)]:
    for h in vals:
        # Check that conversion is reversible
        f = cls.fromh(h).f
        e = cls.fromf(f).h
        assert (f != f) or (f == -f) or (h == e), f"h={h} e={e} f={f}"
        # Check intermediate values
        j = f"{int(h, 16) + 1:04x}"[-len(h):]
        g = cls.fromh(j).f
        if (f == f) and (g == g) and abs(f) < float('inf') and abs(g) < float('inf') and (f != -f) and (g != -g):
            sign = -1 if ((f + g) / 2) < 0 else 1
            # Check that halfway rounds to even
            b = cls.fromf((f + g) / 2).b
            assert b[-1] == '0', f"{cls.__name__} h={h} j={j} b={b} f={f} g={g}"
            # Check rounding up
            k = cls.fromf((f + g) / 2 + sign * 1e-10).h
            assert k == j, f"{cls.__name__} h={h} j={j} k={k} f={f} g={g}"
            # Check rounding down
            k = cls.fromf((f + g) / 2 - sign * 1e-10).h
            assert k == h, f"{cls.__name__} h={h} j={j} k={k} f={f} g={g}"

# Test boundary values
for cls in [E5M2, E4M3, FP16]:
    # Assert nan
    assert cls.fromf(float('nan')) == cls.fromf(float('nan'))
    assert cls.fromf(float('nan')).f != cls.fromf(float('nan')).f
    # Assert inf
    assert cls.fromf(float('inf')).f >= cls.MAX
    assert cls.fromf(float('-inf')).f <= -cls.MAX
    # Assert max less than inf
    assert cls.fromf(cls.MAX).f < float('inf')
    assert cls.fromf(-cls.MAX).f > float('-inf')
    # Assert max greater than 1
    assert cls.fromf(cls.MAX).f > 1
    assert cls.fromf(-cls.MAX).f < -1
    # Assert min less than 1
    assert cls.fromf(cls.MIN).f < 1
    assert cls.fromf(-cls.MIN).f > -1
    # Assert min greater than 0
    assert cls.fromf(cls.MIN).f > 0
    assert cls.fromf(-cls.MIN).f < 0
    # Assert half min rounds to 0
    assert cls.fromf(cls.MIN / 2).f == 0
    assert cls.fromf(-cls.MIN / 2).f == 0
    # Assert epsilon more than half min rounds up to min
    assert cls.fromf(cls.MIN / 2 + 1e-10).f == cls.MIN
    assert cls.fromf(-cls.MIN / 2 - 1e-10).f == -cls.MIN
    # Assert epsilon less than half min rounds down to 0
    assert cls.fromf(cls.MIN / 2 - 1e-10).f == 0
    assert cls.fromf(-cls.MIN / 2 + 1e-10).f == 0
    # Assert epsilon more than max rounds up to inf
    assert cls.fromf(cls.MAX + 1e-10) == cls.fromf(float('inf'))
    assert cls.fromf(-cls.MAX - 1e-10) == cls.fromf(float('-inf'))


# %%
# Use binary search to find the nearest e5 value
def ftoe5(f):
    assert isinstance(f, float), f"f={repr(f)}"
    sig = '1' if f < 0 else '0'
    if f != f:
        return '01111101'
    if abs(f) > E5MAX:
        return sig + '1111100'
    if abs(f) <= E5MIN / 2:
        return '00000000'
    if abs(f) <= E5MIN:
        return sig + '0000001'

    val = sig
    for i in range(1, 8):
        assert len(val) == i
        low = val + '0' + '1' * (7 - i)
        high = val + '1' + '0' * (7 - i)
        if abs(f - e5tof(low)) < abs(f - e5tof(high)):
            val = val + '0'
        else:
            val = val + '1'

    return val

# Same but for fp16
def ftofp16(f):
    assert isinstance(f, float), f"f={repr(f)}"
    sig = '1' if f < 0 else '0'
    if f != f:
        return '0111110000000001'
    if abs(f) > FP16MAX:
        return sig + '111110000000000'
    if abs(f) <= FP16MIN / 2:
        return '0000000000000000'
    if abs(f) <= FP16MIN:
        return sig + '000000000000001'

    val = sig
    for i in range(1, 16):
        assert len(val) == i
        low = val + '0' + '1' * (15 - i)
        high = val + '1' + '0' * (15 - i)
        if abs(f - fp16tof(low)) < abs(f - fp16tof(high)):
            val = val + '0'
        else:
            val = val + '1'

    return val

# Test all of them
for i in range(256):
    e5tof(f"{i:08b}")
# Test random floats
for _ in range(100000):
    f = random.uniform(-E5MAX, E5MAX)
    e = ftoe5(f)
    ef = e5tof(e)
    ed = abs(f - ef)
    n = f"{int(e, 2) + 1:08b}"
    nf = e5tof(n)
    nd = abs(f - nf)
    p = f"{int(e, 2) - 1:08b}"
    pf = e5tof(p)
    pd = abs(f - pf)
    if nd < ed:
        print(f"f={f}, e={e}, ef={ef}")
        print(f"n={n}, nf={nf}")
        print(f"ed={ed}, nd={nd}")
        assert False
    if pd < ed:
        print(f"f={f}, e={e}, ef={ef}")
        print(f"p={p}, pf={pf}")
        print(f"ed={ed}, pd={pd}")
        assert False

# Test FP16
for _ in range(1000000):
    f = random.uniform(-FP16MAX, FP16MAX)
    e = ftofp16(f)
    ef = fp16tof(e)
    ed = abs(f - ef)
    n = f"{int(e, 2) + 1:016b}"
    nf = fp16tof(n)
    nd = abs(f - nf)
    p = f"{int(e, 2) - 1:016b}"
    pf = fp16tof(p)
    pd = abs(f - pf)
    if nd < ed:
        print(f"f={f}, e={e}, ef={ef}")
        print(f"n={n}, nf={nf}")
        print(f"ed={ed}, nd={nd}")
        assert False
    if pd < ed:
        print(f"f={f}, e={e}, ef={ef}")
        print(f"p={p}, pf={pf}")
        print(f"ed={ed}, pd={pd}")
        assert False

# %%

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



f = e5tof('00000001') * e5tof('00011000')
(f - fp16tof(ftofp16(f))) == -f


# %% Test FP16 more
for _ in range(100000):
    a = random.randint(0, 2 ** 16 - 1)
    g = fp16tof(f"{a:016b}")
    f = random.choice([g * 1.00000000000001, g * 0.999999999999])
    e = ftofp16(f)
    ef = fp16tof(e)
    ed = abs(f - ef)
    n = f"{int(e, 2) + 1:016b}"
    nf = fp16tof(n)
    nd = abs(f - nf)
    if abs(f) >= FP16MAX:
        if abs(ef) != float('inf'):
            print(f"f={f}, e={e}, ef={ef}")
            print(f"p={p}, pf={pf}")
            print(f"ed={ed}, pd={pd}")
            assert False
    else:
        if nd < ed:
            print(f"f={f}, e={e}, ef={ef}")
            print(f"n={n}, nf={nf}")
            print(f"ed={ed}, nd={nd}")
            assert False
        if int(e):
            p = f"{int(e, 2) - 1:016b}"
            pf = fp16tof(p)
            pd = abs(f - pf)
            if pd < ed:
                print(f"f={f}, e={e}, ef={ef}")
                print(f"p={p}, pf={pf}")
                print(f"ed={ed}, pd={pd}")
                assert False