Safe and Sophie Germain primes generator
========================================

This is a small repo for a problem where I needed to generate _safe_ prime numbers for a cryptography game.

After writing this small code, which was sufficient for my needs, I found that it could be a good example to learn profiling and benchmarking of code.

First Iteration
===============

My initial implementation used a simple algorithm which I've seen referred to as _trial division_.

The `is_prime()` function checks whether a number `n` is prime by first handling small/even cases, then testing every odd number from 3 up to √n + 1 as a potential divisor. If any divides `n` evenly, it's composite; otherwise it's prime. The key insight is that if `n` has a factor larger than √n, it must also have a corresponding factor smaller than √n, so you only need to check up to that bound.

We need to use the `is_prime()` twice for each candidate `n` - we need to check that *both* `n` and `2n + 1` are prime.

Time complexity analysis
------------------------

A single trial division test on `n` is O(√n). As previously mentioned, each Sophie Germain check does two prime checks via `is_prime()` - one for `n` and one for `2n + 1`. Therefore each candidate costs O(√n).

By the prime number theorem, primes near `n` have average gaps of roughly O(ln(n)), and Sophie Germain primes are rarer still - heuristically gaps of O(ln²(n)), via the Hardy-Littlewood conjecture.

So the expected total cost is roughly O(√n⋅ln²(n)) - though this is a heuristic estimate, not a proven bound, since the distribution of Sophie Germain primes is only conjectural.

Note
----

There's also a subtle precision issue worth noting: casting to `double` in `sqrt((double)n)` loses precision for very large `unsigned long long` values (above ~2^53), which could make the `sqrt(n) + 1` bound inaccurate and produce wrong results for numbers near the top of the 64-bit range. As this is was just intended for relatively small safe primes, it shouldn't be much of an issue, but worth noting if you want to go close to the 64-bit range.

Profiling bottleneck analysis
-----------------------------

### Benchmarking with Hyperfine

```
Benchmark 1: build/sophie-germain-prime-finder 1000000000000000000
  Time (mean ± σ):      9.351 s ±  0.035 s    [User: 9.236 s, System: 0.036 s]
  Range (min … max):    9.298 s …  9.411 s    10 runs
```

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
