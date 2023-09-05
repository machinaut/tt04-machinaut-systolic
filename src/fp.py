#!/usr/bin/env python
# %%  Floating point classes
import random
from dataclasses import dataclass
from itertools import product


def is_bin(s, l=None):
    return (
        isinstance(s, str)
        and len(s)
        and all(c in "01" for c in s)
        and (l is None or len(s) == l)
    )


def is_hex(s, l=None):
    return (
        isinstance(s, str)
        and len(s)
        and all(c in "0123456789abcdef" for c in s.lower())
        and (l is None or len(s) == l)
    )


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
        sig = -1 if self.sig == "1" else 1
        exp = int(self.exp, 2) - 2 ** (self.e_l - 1) + 1
        man = int(self.man, 2) / (2**self.m_l)
        assert 0 <= man < 1, f"man={repr(man)}"
        if self.e_l == 5:
            if self.exp == "1" * self.e_l:
                return float("nan") if (man > 0) else sig * float("inf")
        else:  # Special case for E4M3
            if (self.exp == "1" * self.e_l) and (self.man == "1" * self.m_l):
                return float("nan")
        if int(self.exp) == 0:
            return sig * (2 ** (exp + 1)) * man
        return sig * (2**exp) * (1.0 + man)

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
        sig = "1" if f < 0 else "0"
        if f != f:  # NaN
            return cls("0", "1" * cls.e_l, "1" * cls.m_l)
        if cls.e_l == 5:  # Normal case
            if abs(f) > cls.MAX:  # Inf
                return cls(sig, "1" * cls.e_l, "0" * cls.m_l)
        else:  # Special case for E4M3
            if abs(f) >= cls.MAX:  # Saturate to MAX
                return cls(sig, "1" * cls.e_l, "1" * (cls.m_l - 1) + "0")
        if abs(f) <= cls.MIN / 2:  # Zero
            return cls("0", "0" * cls.e_l, "0" * cls.m_l)
        if abs(f) <= cls.MIN:  # Min
            return cls(sig, "0" * cls.e_l, "0" * (cls.m_l - 1) + "1")
        # Compare bit by bit
        val = sig
        size = cls.e_l + cls.m_l
        for i in range(1, 1 + size):
            assert len(val) == i
            low = val + "0" + "1" * (size - i)
            high = val + "1" + "0" * (size - i)
            low_diff = abs(f - cls.fromb(low).f)
            high_diff = abs(f - cls.fromb(high).f)
            if verbose:
                print(f"i={i} val={val} low={low}, high={high}")
                print(f"low_diff={low_diff}, high_diff={high_diff}")
            if low_diff == high_diff:
                val = val + ("0" if i == size else "1")
            elif (low_diff < high_diff) or (high_diff != high_diff):
                val = val + "0"
            else:
                val = val + "1"
        return cls.fromb(val)

    @classmethod
    def rand(cls):
        sig = random.choice("01")
        exp = "".join(random.choice("01") for _ in range(cls.e_l))
        man = "".join(random.choice("01") for _ in range(cls.m_l))
        # Normalize to get standard NaN / Zero
        return cls.fromf(cls(sig, exp, man).f)


@dataclass
class FP16(Float):
    e_l: int = 5
    m_l: int = 10
    MAX: float = 65504.0
    MIN: float = 2**-24

    @classmethod
    def fromb(cls, b):
        assert is_bin(b, 16), f"b={repr(b)}"
        return cls(b[0], b[1:6], b[6:])


@dataclass
class E5M2(Float):
    e_l: int = 5
    m_l: int = 2
    MAX: float = 57344.0
    MIN: float = 2**-16

    @classmethod
    def fromb(cls, b):
        assert is_bin(b, 8), f"b={repr(b)}"
        return cls(b[0], b[1:6], b[6:])


@dataclass
class E4M3(Float):
    e_l: int = 4
    m_l: int = 3
    MAX: float = 448.0
    MIN: float = 2**-9

    @classmethod
    def fromb(cls, b):
        assert is_bin(b, 8), f"b={repr(b)}"
        return cls(b[0], b[1:5], b[5:])


# Tests for floating point, only if run as main
if __name__ == "__main__":
    # Hard-coded NaN/Inf/Max/Min values
    assert FP16.fromf(float("nan")).h == "7fff"
    assert FP16.fromf(float("inf")).h == "7c00"
    assert FP16.fromh("0001").f == FP16.MIN
    assert FP16.fromh("7bff").f == FP16.MAX
    assert E5M2.fromf(float("nan")).h == "7f"
    assert E5M2.fromf(float("inf")).h == "7c"
    assert E5M2.fromh("7b").f == E5M2.MAX
    assert E5M2.fromh("01").f == E5M2.MIN
    assert E4M3.fromf(float("nan")).h == "7f"
    assert E4M3.fromf(float("inf")).h == "7e"  # Note this is MAX value
    assert E4M3.fromh("7e").f == E4M3.MAX
    assert E4M3.fromh("01").f == E4M3.MIN

    suffixes = ["00", "01", "7e", "7f", "80", "81", "fe", "ff"]
    val8s = [f"{i:02x}" for i in range(256)]
    val16s = [i + j for (i, j) in product(val8s, suffixes)]
    for cls, vals in [(E5M2, val8s), (E4M3, val8s), (FP16, val16s)]:
        for h in vals:
            # Check that conversion is reversible
            f = cls.fromh(h).f
            e = cls.fromf(f).h
            assert (f != f) or (f == -f) or (h == e), f"h={h} e={e} f={f}"
            # Check intermediate values
            j = f"{int(h, 16) + 1:04x}"[-len(h) :]
            g = cls.fromh(j).f
            if (
                (f == f)
                and (g == g)
                and abs(f) < float("inf")
                and abs(g) < float("inf")
                and (f != -f)
                and (g != -g)
            ):
                sign = -1 if ((f + g) / 2) < 0 else 1
                # Check that halfway rounds to even
                b = cls.fromf((f + g) / 2).b
                assert b[-1] == "0", f"{cls.__name__} h={h} j={j} b={b} f={f} g={g}"
                # Check rounding up
                k = cls.fromf((f + g) / 2 + sign * 1e-10).h
                assert k == j, f"{cls.__name__} h={h} j={j} k={k} f={f} g={g}"
                # Check rounding down
                k = cls.fromf((f + g) / 2 - sign * 1e-10).h
                assert k == h, f"{cls.__name__} h={h} j={j} k={k} f={f} g={g}"

    # Test boundary values
    for cls in [E5M2, E4M3, FP16]:
        # Assert nan
        assert cls.fromf(float("nan")) == cls.fromf(float("nan"))
        assert cls.fromf(float("nan")).f != cls.fromf(float("nan")).f
        # Assert inf
        assert cls.fromf(float("inf")).f >= cls.MAX
        assert cls.fromf(float("-inf")).f <= -cls.MAX
        # Assert max is normalized
        assert cls.fromf(cls.MAX).f == cls.MAX
        assert cls.fromf(-cls.MAX).f == -cls.MAX
        # Assert max less than inf
        assert cls.fromf(cls.MAX).f < float("inf")
        assert cls.fromf(-cls.MAX).f > float("-inf")
        # Assert max greater than 1
        assert cls.fromf(cls.MAX).f > 1
        assert cls.fromf(-cls.MAX).f < -1
        # Assert min is normalized
        assert cls.fromf(cls.MIN).f == cls.MIN
        assert cls.fromf(-cls.MIN).f == -cls.MIN
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
        assert cls.fromf(cls.MAX + 1e-10) == cls.fromf(float("inf"))
        assert cls.fromf(-cls.MAX - 1e-10) == cls.fromf(float("-inf"))
        # Try drawing 100 random values, check that some are different
        for _ in range(100):
            vals = [cls.rand() for _ in range(100)]
            hexs = [val.h for val in vals]
            assert len(set(hexs)) > 10, f"cls={cls.__name__} hexs={hexs}"
