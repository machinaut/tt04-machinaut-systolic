#!/usr/bin/env python
# %%
import ctypes
import random

def is_bits(s, l=None):
    return isinstance(s, str) and len(s) and all(c in '01' for c in s) and (l is None or len(s) == l)

def f2u(f):
    return ctypes.c_uint32.from_buffer(ctypes.c_float(f)).value

def u2f(u):
    return ctypes.c_float.from_buffer(ctypes.c_uint32(u)).value

def s2u(s, l=None):
    assert is_bits(s, l), (s, len(s), l)
    return int(s,2)

def u2s(u, l):
    assert isinstance(u, int) and isinstance(l, int) and u >= 0 and l > 0, (u, l)
    v = f"{u:0{l}b}"
    assert is_bits(v, l), (v, len(v), l)
    return v

def s2f(s):
    return u2f(s2u(s, 32))

def f2s(f):
    return u2s(f2u(f), 32)

def f2f(f):
    return u2f(f2u(f))

def flip(s):
    assert is_bits(s), s
    v = ''.join('1' if c == '0' else '0' for c in s)
    assert is_bits(v, len(s)), (v, len(s))
    return v

def r2s(n):
    return u2s(random.randint(0, 2**n - 1), n)

def s16(s, e, m):
    return u2s(s, 1) + u2s(e, 8) + u2s(m, 7)

def s32(s, e, m):
    return u2s(s, 1) + u2s(e, 8) + u2s(m, 23)

def fp32(s, e, m):
    return s2f(s32(s, e, m))

def bf16(s, e, m):
    return s2f(s16(s, e, m) + '0' * 16)

def s2q(exp, man):
    assert isinstance(exp, int) and 0 <= exp <= 255, exp
    assert is_bits(man, 23), (man, len(man), 23)
    if exp == 255:
        q = 'nan' if int(man) else 'inf'
    elif 0 < exp < 255:
        q = '01' + man
    else:
        q = '00' + man
        exp = 1
    assert is_bits(q, 25), (q, len(q), 25)
    return exp, q

def q2s(exp, q):
    assert isinstance(exp, int) and 1 <= exp <= 255, exp
    if exp == 255:
        man = ('0' * 23) if (q == 'inf') else ('0' * 22 + '1')
    elif int(q) == 0:
        exp = 0
        man = '0' * 23
    elif q[:2] == '00':
        assert exp == 1, exp
        exp = 0
        man = q[2:]
    else:
        man = q[2:]
    return exp, man


def round(exp, q, grd, rnd, stk, verbose=False):
    assert isinstance(exp, int) and 1 <= exp <= 254, exp
    assert is_bits(q, 25), (q, len(q), 25)
    assert is_bits(grd, 1), (grd, len(grd), 1)
    assert is_bits(rnd, 1), (rnd, len(rnd), 1)
    assert is_bits(stk, 1), (stk, len(stk), 1)
    odd = q[24]
    if grd == '1' and (rnd == '1' or stk == '1' or odd == '1'):
        if verbose:
            print(f"Round up q={q} grd={grd} rnd={rnd} stk={stk} odd={odd}")
        q = u2s(s2u(q) + 1, 26)[1:]
        if q[0] == '1':
            exp += 1
            if exp == 255:
                q = 'inf'
            else:
                q = '0' + q[:24]
    return exp, q

# Multiply two BFloat16 binary strings and return a FP32 binary string
def mul(a, b, verbose=False):
    if verbose:
        vprint = print
    else:
        vprint = lambda *args, **kwargs: None
    vprint(f"mul(a={repr(a)}, b={repr(b)})")
    assert is_bits(a, 16), (a, len(a), 16)
    assert is_bits(b, 16), (b, len(b), 16)
    # Extract parts
    a_sig, a_exp, a_man = s2u(a[0]), s2u(a[1:9]), a[9:]
    b_sig, b_exp, b_man = s2u(b[0]), s2u(b[1:9]), b[9:]
    a_nan = (a_exp == 255) and int(a_man)
    a_inf = (a_exp == 255) and not int(a_man)
    a_sub = (a_exp == 0) and int(a_man)
    a_zero = (a_exp == 0) and not int(a_man)
    b_nan = (b_exp == 255) and int(b_man)
    b_inf = (b_exp == 255) and not int(b_man)
    b_sub = (b_exp == 0) and int(b_man)
    b_zero = (b_exp == 0) and not int(b_man)
    assert 0 <= a_exp <= 255, a_exp
    assert 0 <= b_exp <= 255, b_exp
    p_sig = int(a_sig ^ b_sig)
    p_nan = u2s(p_sig, 1) + u2s(255, 8) + u2s(1, 23)
    p_inf = u2s(p_sig, 1) + u2s(255, 8) + u2s(0, 23)
    p_zero = u2s(p_sig, 1) + u2s(0, 8) + u2s(0, 23)

    if a_nan or b_nan or (a_inf and b_zero) or (a_zero and b_inf):
        return p_nan
    elif a_inf or b_inf:
        return p_inf
    elif a_zero or b_zero or (a_sub and b_sub):
        return p_zero
    
    if a_sub:
        assert not b_sub, f"expected only one sub a={a} b={b}"
        # Swap
        a, b = b, a
        a_sig, b_sig = b_sig, a_sig
        a_exp, b_exp = b_exp, a_exp
        a_man, b_man = b_man, a_man
        a_nan, b_nan = b_nan, a_nan
        a_inf, b_inf = b_inf, a_inf
        a_sub, b_sub = b_sub, a_sub
        a_zero, b_zero = b_zero, a_zero
    
    assert not a_sub, f"expected only one sub a={a} b={b}"

    # Convert to Q
    assert 1 <= a_exp <= 254, f"a_exp={a_exp}"
    a_q = '1' + a_man
    if b_exp == 0:
        assert int(b_man), f"b_man={b_man}"
        b_lead_zeros = len(b_man) - len(b_man.lstrip('0'))
        assert 0 <= b_lead_zeros <= 6, f"b_lead_zeros={b_lead_zeros} b_man={b_man}"
        b_exp -= b_lead_zeros
        b_q = b_man[b_lead_zeros:] + '0' * (1 + b_lead_zeros)
    else:
        assert b_exp < 255, b_exp
        b_q = '1' + b_man
    assert is_bits(a_q, 8), (a_q, len(a_q), 8)
    assert is_bits(b_q, 8), (b_q, len(b_q), 8)
    vprint(f"a_q={a_q} b_q={b_q}")
    p_q = u2s(s2u(a_q) * s2u(b_q), 16)
    assert int(p_q), f"should be nonzero: {p_q}"
    p_exp = a_exp + b_exp - 127
    vprint(f"p_q={p_q} p_exp={p_exp}")
    # Pad out to 25 bits based on exponent
    if p_exp <= -8:
        p_q = '0' * 9 + p_q
        p_exp += 9
    elif p_exp <= 0:
        p_q = '0' * (1 - p_exp) + p_q + '0' * (8 + p_exp)
        p_exp = 1
    else:
        p_q = p_q + '0' * 9
    assert is_bits(p_q, 25), (p_q, len(p_q), 25)
    vprint(f"p_q={p_q} p_exp={p_exp}")
    # Shift until positive exp
    grd = rnd = stk = '0'
    if p_exp <= 0:
        vprint(f"Negative exp, Right shift={1-p_exp}")
        shifts = 0
        orig_p_q = p_q
        orig_p_exp = p_exp
        target = min(18, 1-p_exp)
        # while (int(p_q) or int(grd) or int(rnd)) and p_exp <= 0:
        while shifts < 18 and p_exp <= 0:
            assert is_bits(p_q, 25), (p_q, len(p_q), 25)
            stk = '1' if stk == '1' else rnd
            rnd = grd
            grd = p_q[24]
            p_q = '0' + p_q[:24]
            p_exp += 1
            shifts += 1
        assert shifts == target, f"shifts={shifts} target={target} orig_p_q={orig_p_q} orig_p_exp={orig_p_exp}"
        assert shifts <= 18, f"shifts={shifts} orig_p_q={orig_p_q}"
        p_exp = 1
        vprint(f"p_q={p_q} p_exp={p_exp} grd={grd} rnd={rnd} stk={stk}")
    elif p_q[0] == '1':
        assert p_q[24] == '0', f"p_q={p_q}"
        p_q = '0' + p_q[:24]
        p_exp += 1
    assert is_bits(p_q, 25), (p_q, len(p_q), 25)
    if p_exp >= 255:
        return p_inf
    assert 1 <= p_exp <= 255, f"p_exp={p_exp}"
    vprint(f"p_q={p_q} p_exp={p_exp} grd={grd} rnd={rnd} stk={stk}")
    p_exp, p_q = round(p_exp, p_q, grd, rnd, stk, verbose=verbose)
    vprint(f"p_q={p_q} p_exp={p_exp}, post-round")
    assert 1 <= p_exp <= 255, f"p_exp={p_exp}"
    if p_exp == 255:
        return p_inf
    # Convert to FP32
    assert 1 <= p_exp <= 254, f"p_exp={p_exp}"
    assert p_q[0] == '0', f"p_q={p_q}"
    if p_q[1] == '1':
        p_man = p_q[2:]
    else:
        assert p_exp == 1, f"p_q={p_q} p_exp={p_exp}"
        p_exp = 0
        p_man = p_q[2:]
    vprint(f"p_sig={p_sig} p_exp={p_exp} p_man={p_man}")
    p = u2s(p_sig, 1) + u2s(p_exp, 8) + p_man
    assert is_bits(p, 32), (p, len(p), 32)
    return p


def add(a, b, verbose=False):
    if verbose:
        vprint = print
    else:
        vprint = lambda *args, **kwargs: None
    vprint(f"add(a={repr(a)}, b={repr(b)})")
    assert is_bits(a, 32), (a, len(a), 32)
    assert is_bits(b, 32), (b, len(b), 32)
    # Extract parts
    a_sig, a_exp, a_man = s2u(a[0]), s2u(a[1:9]), a[9:]
    b_sig, b_exp, b_man = s2u(b[0]), s2u(b[1:9]), b[9:]
    a_nan = (a_exp == 255) and int(a_man)
    a_inf = (a_exp == 255) and not int(a_man)
    a_sub = (a_exp == 0) and int(a_man)
    a_zero = (a_exp == 0) and not int(a_man)
    b_nan = (b_exp == 255) and int(b_man)
    b_inf = (b_exp == 255) and not int(b_man)
    b_sub = (b_exp == 0) and int(b_man)
    b_zero = (b_exp == 0) and not int(b_man)
    assert 0 <= a_exp <= 255, a_exp
    assert 0 <= b_exp <= 255, b_exp

    if a_exp < b_exp or (a_exp == b_exp and int(a_man) < int(b_man)):
        # Swap
        a, b = b, a
        a_sig, b_sig = b_sig, a_sig
        a_exp, b_exp = b_exp, a_exp
        a_man, b_man = b_man, a_man
        a_nan, b_nan = b_nan, a_nan
        a_inf, b_inf = b_inf, a_inf
        a_sub, b_sub = b_sub, a_sub
        a_zero, b_zero = b_zero, a_zero
    s_sig = a_sig
    s_nan = u2s(s_sig, 1) + u2s(255, 8) + u2s(1, 23)
    s_inf = u2s(s_sig, 1) + u2s(255, 8) + u2s(0, 23)
    # Zero sign is special cased, and only negative if both inputs are negative, else positive
    s_zero = u2s(int(a_sig and b_sig), 1) + u2s(0, 8) + u2s(0, 23)

    if a_nan or b_nan or (a_inf and b_inf and a_sig != b_sig):
        return s_nan
    elif a_inf or b_inf:
        return s_inf
    elif a_zero and b_zero:
        return s_zero
    elif a_zero or b_zero:
        if a_zero:
            return b
        else:
            return a
    
    # Convert to Q
    if a_exp == 0:
        assert b_exp == 0, f"b_exp={b_exp}"
        a_q = '00' + a_man
        a_exp = 1
    else:
        a_q = '01' + a_man
    if b_exp == 0:
        b_q = '00' + b_man
        b_exp = 1
    else:
        b_q = '01' + b_man
    assert is_bits(a_q, 25), (a_q, len(a_q), 25)
    assert is_bits(b_q, 25), (b_q, len(b_q), 25)
    assert 1 <= a_exp <= 254, f"a_exp={a_exp}"
    assert 1 <= b_exp <= a_exp, f"b_exp={b_exp}"
    vprint(f"a_q={a_q} a_exp={a_exp}")
    vprint(f"b_q={b_q} b_exp={b_exp}")
    # Shift until matching exp
    grd = rnd = stk = '0'
    # # Flip if subtracting
    # if a_sig != b_sig:
    #     vprint("Subtraction, flipping b_q")
    #     carry = 1
    #     b_q = flip(b_q)
    #     vprint(f"b_q={b_q} b_exp={b_exp} grd={grd} rnd={rnd} stk={stk}")
    # else:
    #     carry = 0
    # Shift to match exp
    if a_exp != b_exp:
        target_shift = a_exp - b_exp
        vprint(f"Smaller exp, Right shift={target_shift}")
        shifts = 0
        orig_b_q = b_q
        b_q_left_zero = len(b_q) - len(b_q.lstrip('0'))
        target = min(target_shift, 27 - b_q_left_zero)
        while (int(b_q) or int(grd) or int(rnd)) and b_exp < a_exp:
            assert is_bits(b_q, 25), (b_q, len(b_q), 25)
            stk = '1' if stk == '1' else rnd
            rnd = grd
            grd = b_q[24]
            b_q = '0' + b_q[:24]
            b_exp += 1
            shifts += 1
        assert shifts <= 26, f"shifts={shifts} target_shift={target_shift} orig_b_q={orig_b_q} target={target}"
        assert shifts == target,  f"shifts={shifts} target_shift={target_shift} orig_b_q={orig_b_q} target={target}"
        assert b_exp == a_exp or not int(b_q), f"b_exp={b_exp} a_exp={a_exp} b_q={b_q}"
        vprint(f"b_q={b_q} b_exp={b_exp} grd={grd} rnd={rnd} stk={stk}")
    # Add to get sum
    # vprint(f"Adding carry={carry}")
    # s_q = u2s(s2u(a_q) + s2u(b_q) + carry, 26)[1:]
    # Conditionally add or subtract
    if a_sig == b_sig:
        vprint("Adding")
        s_q = u2s(s2u(a_q) + s2u(b_q), 26)[1:]
    else:
        vprint("Subtracting")
        sub_q = u2s(s2u(a_q + '000') - s2u(b_q + grd + rnd + stk), 29)[1:]
        s_q, grd, rnd, stk = sub_q[:25], sub_q[25], sub_q[26], sub_q[27]
    assert is_bits(s_q, 25), (s_q, len(s_q), 25)
    s_exp = a_exp
    vprint(f"s_q={s_q} s_exp={s_exp} grd={grd} rnd={rnd} stk={stk}")
    if s_q[0] == '1':  # right shift
        vprint("Right shift 1")
        stk = '1' if stk == '1' else rnd
        rnd = grd
        grd = s_q[24]
        s_q = '0' + s_q[:24]
        s_exp += 1
    elif s_q[1] == '1':  # No action
        vprint("No shift")
    elif s_exp > 1:
        assert s_q[0] == '0', f"s_q={s_q}"
        vprint("Left shift")
        leftshifts = 0
        orig_s_q = s_q
        target = min(len(s_q) - len(s_q.lstrip('0')), s_exp) - 1
        while s_q[1] == '0' and s_exp > 1:
            s_exp -= 1
            s_q = s_q[1:] + grd
            grd = rnd
            rnd = stk
            stk = '0'
            leftshifts += 1
        # TODO: this should get up to 27 eventually I think
        assert leftshifts == target, f"leftshifts={leftshifts} target={target} orig_s_q={orig_s_q}"
        assert leftshifts <= 23, f"leftshifts={leftshifts} orig_s_q={orig_s_q}"
    if s_exp == 255:
        return s_inf
    assert 1 <= s_exp <= 254, f"s_exp={s_exp}"
    assert is_bits(s_q, 25), (s_q, len(s_q), 25)
    vprint(f"s_q={s_q} s_exp={s_exp} grd={grd} rnd={rnd} stk={stk}")
    s_exp, s_q = round(s_exp, s_q, grd, rnd, stk, verbose=verbose)
    vprint(f"s_q={s_q} s_exp={s_exp}, post-round")
    if s_exp == 255:
        return s_inf
    assert 1 <= s_exp <= 254, f"s_exp={s_exp}"
    assert is_bits(s_q, 25), (s_q, len(s_q), 25)
    # Convert to FP32
    assert s_q[0] == '0', f"s_q={s_q}"
    if s_q[1] == '1':
        s_man = s_q[2:]
    else:
        assert s_exp == 1, f"s_q={s_q} s_exp={s_exp}"
        s_exp = 0
        s_man = s_q[2:]
        # Special case zero sign
        if not int(s_man):
            s_sig = int(a_sig and b_sig)
    vprint(f"s_sig={s_sig} s_exp={s_exp} s_man={s_man}")
    s = u2s(s_sig, 1) + u2s(s_exp, 8) + s_man
    assert is_bits(s, 32), (s, len(s), 32)
    return s



# # %%
# mans = [0, 1, 2, 3, 4, 5, 6, 7, 8, 0x3ffffe, 0x3fffff, 0x400000, 0x400001, 0x7ffffe, 0x7fffff]
# for a_exp in exps:
#     for a_man in mans:
#         for b_exp in exps:
#             for b_man in mans:
#                 a = '1' + u2s(a_exp, 8) + u2s(a_man, 23)
#                 b = '0' + u2s(b_exp, 8) + u2s(b_man, 23)
#                 show(a, b)

# for a_sig in '01':
#     for a_exp in exps:
#         for a_man in mans:
#             a = a_sig + u2s(a_exp, 8) + u2s(a_man, 7)
#             for b_sig in '01':
#                 for b_exp in exps:
#                     for b_man in mans:
#                         b = b_sig + u2s(b_exp, 8) + u2s(b_man, 7)
#                         pairs.append((a, b))

# # for a, b in pairs:
# while True:
#     # a, b = r2s(16), r2s(16)
#     # af = s2f(a + '0' * 16)
#     # bf = s2f(b + '0' * 16)
#     a, b = r2s(32), r2s(32)
#     af = s2f(a)
#     bf = s2f(b)
#     # ef = af * bf
#     # c = mul(a, b)
#     ef = af + bf
#     # print(f"a={a} b={b} af={af} bf={bf}")
#     c = add(a, b, verbose=False)
#     cf = s2f(c)
#     df = f2f(ef)
#     d = f2s(df)
#     ce = ef - cf
#     de = ef - df
#     d_sig, d_exp, d_man = s2u(d[0]), s2u(d[1:9]), d[9:]
#     # print(f"d_sig={d_sig} d_exp={d_exp} d_man={d_man}")
#     # print(f"c={c} d={d} cf={cf} df={df}")
#     # print(f"ce={ce} de={de} ef={ef}")
#     assert (df != df and cf != cf) or d == c, f"({repr(a)}, {repr(b)})"

sigs = [0, 1]
exps = list(range(8)) + list(range(18,27)) + list(range(100, 128)) + list(range(251, 256))
mans32 = list(range(8)) + list(range(0x3ffffa, 0x400008)) + list(range(0x5ffffa, 0x600008)) + list(range(0x7ffff0, 0x800000))
mans16 = list(range(8)) + list(range(0x3a, 0x40)) + list(range(0x5a, 0x60)) + list(range(0x7a, 0x80))

def bf16r():
    s = random.choice(sigs)
    e = random.choice(exps)
    m = random.choice(mans16)
    v = f2s(bf16(s, e, m))
    assert is_bits(v, 32) and v[16:] == '0' * 16, (v, len(v), 32)
    return v[:16]

def fp32r():
    s = random.choice(sigs)
    e = random.choice(exps)
    m = random.choice(mans32)
    v = f2s(fp32(s, e, m))
    assert is_bits(v, 32), (v, len(v), 32)
    return v

def triple():
    a = bf16r()
    b = bf16r()
    c = fp32r()
    return a, b, c


def check(a, b, c, verbose=True):
    assert is_bits(a, 16), (a, len(a), 16)
    assert is_bits(b, 16), (b, len(b), 16)
    assert is_bits(c, 32), (c, len(c), 32)
    af, bf, cf = s2f(a + '0' * 16), s2f(b + '0' * 16), s2f(c)
    d = add(mul(a, b, verbose=verbose), c, verbose=verbose)
    df = s2f(d)
    ef = f2f(f2f(af * bf) + cf)
    e = f2s(ef)
    if verbose:
        print(f"d={d} df={df}\ne={e} ef={ef}")
    assert (df != df and ef != ef) or d == e, f"(a={repr(a)}, b={repr(b)}, c={repr(c)})"

# check(a='0000000001111110', b='1011010100000011', c='00000000000000000000000000000100')


while True:
    a, b, c = r2s(16), r2s(16), r2s(32)
    # a, b, c = triple()
    check(a, b, c, verbose=False)




# assert round(1, '0111000000000000000000100', '0', '0', '0') == (1, '0111000000000000000000100')
# assert round(1, '0111000000000000000000000', '1', '1', '0') == (1, '0111000000000000000000001')
# assert round(1, '0111000000000000000000000', '0', '1', '0') == (1, '0111000000000000000000000')
# assert round(1, '0111000000000000000000000', '1', '1', '1') == (1, '0111000000000000000000001')
# assert round(1, '0111000000000000000000000', '0', '0', '1') == (1, '0111000000000000000000000')
# assert round(1, '0111000000000000000000000', '1', '0', '0') == (1, '0111000000000000000000000')
# assert round(1, '0111000000000000000000001', '1', '0', '0') == (1, '0111000000000000000000010')