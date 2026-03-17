#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <math.h>

// Uses trial division
bool is_prime(unsigned long long n) {
	if (n < 2)
		return false;
	if (n == 2)
		return true;
	if (n % 2 == 0)
		return false;

	unsigned long long sqrt_n_plus_1 = (unsigned long long)sqrt((double)n) + 1;

	for (unsigned long long i = 3; i <= sqrt_n_plus_1; i += 2)
		if (n % i == 0)
			return false;

	return true;
}

bool is_sophie_germain_prime(unsigned long long n) {
	if (!is_prime(n))
		return false;

	return is_prime(2 * n + 1);
}

unsigned long long next_sophie_germain_prime(unsigned long long n) {
	unsigned long long candidate = n + 1;

	if (candidate <= 2) {
		if (is_sophie_germain_prime(2))
			return 2;

		candidate = 3;
	} else if (candidate % 2 == 0) {
		candidate++;
	}

	while (!is_sophie_germain_prime(candidate))
		candidate += 2;

	return candidate;
}

int main(int argc, char *argv[]) {
	unsigned long long input;

	if (argc > 1) {
		input = strtoull(argv[1], NULL, 10);
	} else {
		printf("Enter a number: ");
		if (scanf("%llu", &input) != 1) {
			fprintf(stderr, "Invalid input\n");
			return 1;
		}
	}

	unsigned long long result = next_sophie_germain_prime(input);
	printf("The first Sophie Germain prime greater than %llu is %llu\n", input, result);
	printf("(Verification: 2 * %llu + 1 = %llu is also prime)\n", result, 2 * result + 1);

	return 0;
}
