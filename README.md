Safe and Sophie Germain primes generator
========================================

This is a small repo for a problem where I needed to generate _safe_ prime numbers for a cryptography game.

After writing this small code, which was sufficient for my needs, I found that it could be a good example to learn profiling and benchmarking of code.

First Iteration: Trial Division
===============================

My initial implementation used a simple algorithm which I've seen referred to as _trial division_.

The `is_prime()` function checks whether a number `n` is prime by first handling small/even cases, then testing every odd number from 3 up to √n + 1 as a potential divisor. If any divides `n` evenly, it's composite; otherwise it's prime. The key insight is that if `n` has a factor larger than √n, it must also have a corresponding factor smaller than √n, so you only need to check up to that bound.

We need to use the `is_prime()` twice for each candidate `n` - we need to check that *both* `n` and `2n + 1` are prime.

Time Complexity Analysis
------------------------

A single trial division test on `n` is O(√n). As previously mentioned, each Sophie Germain check does two prime checks via `is_prime()` - one for `n` and one for `2n + 1`. Therefore each candidate costs O(√n).

By the prime number theorem, primes near `n` have average gaps of roughly O(ln(n)), and Sophie Germain primes are rarer still - heuristically gaps of O(ln²(n)), via the Hardy-Littlewood conjecture.

So the expected total cost is roughly O(√n⋅ln²(n)) - though this is a heuristic estimate, not a proven bound, since the distribution of Sophie Germain primes is only conjectural.

Note
----

There's also a subtle precision issue worth noting: casting to `double` in `sqrt((double)n)` loses precision for very large `unsigned long long` values (above ~2^53) of `n` as IEEE-754 64-bit binary floating-point numbers have a 53-bit significand. Casting an `unsigned long long` to `double` rounds it, and `sqrt()` can return a value that's off by 1 or more! This could result in the `sqrt(n) + 1` bound being inaccurate and produce wrong results for numbers near the top of the 64-bit range. As this was just intended for relatively small safe primes, it shouldn't be much of an issue, but worth noting if you want to go close to the 64-bit range.

Profiling Bottleneck Analysis
-----------------------------

### Benchmarking with Hyperfine

```
Benchmark 1: build/sophie-germain-prime-finder 1000000000000000000
  Time (mean ± σ):      9.379 s ±  0.044 s    [User: 9.249 s, System: 0.037 s]
  Range (min … max):    9.325 s …  9.457 s    10 runs
```

### LLVM Profiling

Using LLVM's profiling tools shows (irrelevant lines of code removed):

```
    7|    439|bool is_prime(unsigned long long n) {
    8|    439|	if (n < 2)
    9|      0|		return false;
   10|    439|	if (n == 2)
   11|      0|		return true;
   12|    439|	if (n % 2 == 0)
   13|      0|		return false;
   14|       |
   15|    439|	unsigned long long sqrt_n_plus_1 = (unsigned long long)sqrt((double)n) + 1;
   16|       |
   17|  12.0G|	for (unsigned long long i = 3; i <= sqrt_n_plus_1; i += 2)
                                                                  ^12.0G
   18|  12.0G|		if (n % i == 0)
   19|    420|			return false;
   20|       |
   21|     19|	return true;
   22|    439|}
   23|       |
   24|    421|bool is_sophie_germain_prime(unsigned long long n) {
   25|    421|	if (!is_prime(n))
   26|    403|		return false;
   27|       |
   28|     18|	return is_prime(2 * n + 1);
   29|    421|}
   30|       |
   31|      1|unsigned long long next_sophie_germain_prime(unsigned long long n) {
   32|      1|	unsigned long long candidate = n + 1;
   33|       |
   34|      1|	if (candidate <= 2) {
   35|      0|		if (is_sophie_germain_prime(2))
   36|      0|			return 2;
   37|       |
   38|      0|		candidate = 3;
   39|      1|	} else if (candidate % 2 == 0) {
   40|      0|		candidate++;
   41|      0|	}
   42|       |
   43|    421|	while (!is_sophie_germain_prime(candidate))
               ^1
   44|    420|		candidate += 2;
   45|       |
   46|      1|	return candidate;
   47|      1|}
```

We see that the check happening in `isprime()`'s `for` loop (lines `17-18` here) is the hot path for this implementation.

Some interesting statistics: for the profiling run n=10^18, we found 421 candidates → 18 primes → 1 Sophie Germain prime.

`is_prime()` was called 439 times total, but its inner loop ran ~12 billion iterations. That means on average, each call that didn't bail out early performed tens of millions of trial divisions.

Looking at the funnel, of 421 candidates tested, 403 weren't actually prime i.e. the vast majority of the candidates! The main issue with this implementation is that the majority of candidates are not actually prime, therefore we are wasting a lot of work on expensive primality tests.

Before doing an expensive primality test, we could use a cheap sieve to eliminate candidates divisible by small primes (3, 5, 7, 11, ...). For example, single modulus by 3 can eliminate roughly a third of candidates instantly, before you ever enter the expensive loop! This could be made even more powerful by applying the fast sieve to both `n` and `2n + 1`.

Note that although this sieve performance improvement does not affect the **asymptotic** complexity of the algorithm, it improves the algorithm by large **constant** factors and so is still worth doing - large constant factor improvements matter a lot in practice! As a theoretical example, the difference between O(√n · ln²(n)) with a constant factor of 1 versus the same expression with a constant factor of 0.05 could be the difference between a program that takes minutes and one that takes seconds.

Second Iteration: Adding a Sieve
================================

Adding the aforementioned sieve to `next_sophie_germain_prime()` results in a speedup of 2.72×, or an approximate 63% reduction in execution time. This closely follows the reduction in calls to `is_prime()` (from 12.0 billion to 4.47 billion).

Profiling & Benchmarking Analysis
---------------------------------

### Benchmarking with Hyperfine

```
Benchmark 2: build/sophie-germain-prime-finder 1000000000000000000
  Time (mean ± σ):      3.444 s ±  0.023 s    [User: 3.398 s, System: 0.013 s]
  Range (min … max):    3.422 s …  3.483 s    10 runs
```

### LLVM Profiling

```
    7|     67|bool is_prime(unsigned long long n) {
    8|     67|	if (n < 2)
    9|      0|		return false;
   10|     67|	if (n == 2)
   11|      0|		return true;
   12|     67|	if (n % 2 == 0)
   13|      0|		return false;
   14|       |
   15|     67|	unsigned long long sqrt_n_plus_1 = (unsigned long long)sqrt((double)n) + 1;
   16|       |
   17|  4.47G|	for (unsigned long long i = 3; i <= sqrt_n_plus_1; i += 2)
                                                                  ^4.47G
   18|  4.47G|		if (n % i == 0)
   19|     60|			return false;
   20|       |
   21|      7|	return true;
   22|     67|}
   23|       |
   24|     61|bool is_sophie_germain_prime(unsigned long long n) {
   25|     61|	if (!is_prime(n))
   26|     55|		return false;
   27|       |
   28|      6|	return is_prime(2 * n + 1);
   29|     61|}
   30|       |
   31|      1|unsigned long long next_sophie_germain_prime(unsigned long long n) {
   32|      1|	unsigned long long candidate = n + 1;
   33|       |
   34|      1|	if (candidate <= 2) {
   35|      0|		if (is_sophie_germain_prime(2))
   36|      0|			return 2;
   37|       |
   38|      0|		candidate = 3;
   39|      1|	} else if (candidate % 2 == 0) {
   40|      0|		candidate++;
   41|      0|	}
   42|       |
   43|    421|	while (1) {
               ^1
   44|       |		// Cheap rejection before expensive test
   45|    421|		if (candidate % 3 == 0 || (2 * candidate + 1) % 3 == 0 ||
                                          ^281
   46|    141|		    candidate % 5 == 0 || (2 * candidate + 1) % 5 == 0 ||
                                          ^113
   47|    360|		    candidate % 7 == 0 || (2 * candidate + 1) % 7 == 0) {
                    ^85                   ^73
   48|    360|		    candidate += 2;
   49|    360|			continue;
   50|    360|		}
   51|       |
   52|     61|		if (is_sophie_germain_prime(candidate))
   53|      1|			return candidate;
   54|       |
   55|     60|		candidate += 2;
   56|     60|	}
   57|       |
   58|      0|	return candidate;
   59|      1|}
```

Interestingly the profiling data of the number of times each sieve check is hit closely follows the `(p - 2)/p` survival rate predicted by sieve theory - the same multiplicative structure that underpins the Hardy-Littlewood conjecture for Sophie Germain prime density.

| Stage       | Survival rate       | Predicted | Actual | Error |
|-------------|---------------------|-----------|--------|-------|
| Enter sieve | —                   | 421       | 421    | —     |
| After p=3   | (3−2)/3 = 1/3       | 140.3     | 141    | +0.5% |
| After p=5   | (5−2)/5 = 3/5       | 84.2      | 85     | +1.0% |
| After p=7   | (7−2)/7 = 5/7       | 60.1      | 61     | +1.5% |

The theoretical and profiling results also show the diminishing returns of adding more prime checks to the sieve.

1. p=3 eliminates 2/3 ≈ 66% of candidates
2. p=5 eliminates 2/5 ≈ 40% of the survivors
3. p=7 eliminates 2/7 ≈ 29% of what's left
4. p=11 would eliminate 2/11 ≈ 18%
5. p=13 would eliminate 2/13 ≈ 15%

So we see the most dramatic gains by just using 3, 5 and 7 as the sieve.

Third Iteration: Fixing `sqrt()` Floating-Point Precision Loss
==============================================================

Next I was curious about finding a way to fix the floating point precision loss in the use of the `sqrt()` function in `is_prime()`. Since we don't actually need the precise irrational square root, and only really need _the closest integer to the true square root_, we can use the Newton-Raphson Method to achieve this.

Because I already am looking at profiling and benchmarking, we can simply observe the performance of the new change. For this change, as long as we remain below a 20% decrease in performance, I will deem it an acceptable change in favour of fixing the precision-loss issue.

Profiling & Benchmarking Analysis
---------------------------------

### Benchmarking with Hyperfine

Previous implementation (from Second Implementation):

```
Benchmark 3: build/sophie-germain-prime-finder 1000000000000000000
  Time (mean ± σ):      3.424 s ±  0.010 s    [User: 3.397 s, System: 0.011 s]
  Range (min … max):    3.404 s …  3.453 s    50 runs
```

New implementation (using the Newton-Raphson Method):

```
Benchmark 4: build/sophie-germain-prime-finder 1000000000000000000
  Time (mean ± σ):      3.380 s ±  0.010 s    [User: 3.354 s, System: 0.010 s]
  Range (min … max):    3.362 s …  3.404 s    50 runs
```

Surprisingly, the Newton-Raphson Method is showing slightly better performance than `sqrt()`!

Assembly Analysis
-----------------

This is quite peculiar, because I would think that `math.h`'s `sqrt()` would use a lot of hardware-backed functions for faster speed, however I've benchmarked both implementations several times, and the New-tonRaphson approach is consistently a little faster than the `sqrt()` method.

I decided to investigate the assembly of the Newton-Raphson Method versus `math.h`'s `sqrt()`. This is on a M1 MacBook, compiled using Clang:

```
objdump -d --no-show-raw-insn bin/sophie-germain-prime-finder-mathh-sqrt | grep '^[0-9a-f]* <.*>:'
0000000100000460 <_next_sophie_germain_prime>:
00000001000005cc <_main>:
000000010000069c <__stubs>:
```

The compiler inlined the functions `is_prime()` and `is_sophie_germain_prime()`, however reading a bit, we can find the relevant section as it's quite distinct, I've added some annotations:

```armasm
100000550:     	ucvtf	d0, x0     ; convert to double
100000554:     	fsqrt	d0, d0     ; *hardware* square root
100000558:     	fcvtzu	x16, d0    ; convert result to uint64
10000055c:     	add	x16, x16, #0x1 ; add 1
```

The Newton-Raphson Method implementation did not inline `is_prime()`, but inlined our function `isqrt()`:

```
objdump -d --no-show-raw-insn bin/sophie-germain-prime-finder-newton-raphson | grep '^[0-9a-f]* <.*>:'
0000000100000460 <_is_prime>:
00000001000004f0 <_next_sophie_germain_prime>:
0000000100000688 <_main>:
0000000100000758 <__stubs>:
```

Observing the results of `objdump -d --no-show-raw-insn bin/sophie-germain-prime-finder-newton-raphson | awk '/^[0-9a-f]+ <_is_prime>:/,/^$/'`, we see a more complex assembly:

```armasm
; Initial estimate
100000470:     	clz	x8, x0             ; count leading zeros of n
100000474:     	mov	w9, #0x40          ; (load the value 64 into w9)
100000478:     	sub	w8, w9, w8         ; bit_width = 64 - clz(n)
10000047c:     	lsr	w8, w8, #1         ; bit_width / 2
100000480:     	add	w8, w8, #0x1       ; bit_width / 2 +1
100000484:     	mov	w9, #0x1           ; (load the value 1 into w9)
100000488:     	lsl	x9, x9, x8         ; x = 1 << (bit_width / 2 + 1)
; Loop
10000048c:     	mov	x8, x9             ; x = x_new (or on first iteration)
100000490:     	udiv	x9, x0, x9     ; x_new = n / x
100000494:     	add	x9, x9, x8         ; x_new = n / x + x
100000498:     	lsr	x9, x9, #1         ; x_new = (n / x + x) / 2
10000049c:     	cmp	x9, x8             ; compare x_new with x
1000004a0:     	csel	x9, x9, x8, lo ; x9 = x_new < x ? x_new : x
1000004a4:     	b.lo	0x10000048c    ; if x_new < x, loop again
```

As we can see, even only considering the loop, it's still more instructions than `math.h`'s `sqrt()`, and does not use any special hardware functions for speed. So I'm not exactly sure why this code is faster at this point in time.
