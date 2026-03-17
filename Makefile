CC       = clang
CFLAGS   = -std=c99 -O3 -march=native -flto -funroll-loops \
           -Wall -Wextra -Wpedantic -Wconversion \
           -Wno-incompatible-pointer-types-discards-qualifiers \
           -ffunction-sections -fdata-sections \
	   -MMD -MP

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
    LDFLAGS = -flto -Wl,-dead_strip
else
    LDFLAGS = -flto -Wl,--gc-sections
endif

LDLIBS = -lm

BUILD_DIR = build
SRC_DIR   = src
TARGET    = $(BUILD_DIR)/sophie-germain-prime-finder

SRCS = $(wildcard $(SRC_DIR)/*.c)
OBJS = $(patsubst $(SRC_DIR)/%.c, $(BUILD_DIR)/%.o, $(SRCS))

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) $^ $(LDLIBS) -o $@

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR):
	mkdir -p $@

# Profile-Guided Optimisation (PGO)
#
# PGO_INPUT is the number passed to the prime finder during the
# profiling run. Choose a value representative of real usage so
# that the profile data captures realistic branch and loop behaviour.

PROFILE_INPUT ?= 1000000000000000000
PGO_DIR       = $(BUILD_DIR)/pgo
PGO_INPUT     ?= $(PROFILE_INPUT)

# Platform-specific LLVM tool paths (xcrun on macOS, direct on Linux)
ifeq ($(UNAME), Darwin)
    LLVM_PROFDATA = xcrun llvm-profdata
    LLVM_COV      = xcrun llvm-cov
else
    LLVM_PROFDATA = llvm-profdata
    LLVM_COV      = llvm-cov
endif

pgo: clean
	@echo "=== PGO pass 1: building instrumented binary ==="
	mkdir -p $(BUILD_DIR) $(PGO_DIR)
	$(CC) $(CFLAGS) -fprofile-generate=$(PGO_DIR) \
		$(SRCS) \
		$(LDFLAGS) $(LDLIBS) -fprofile-generate=$(PGO_DIR) \
		-o $(TARGET)
	@echo "=== PGO pass 2: profiling with input $(PGO_INPUT) ==="
	$(TARGET) $(PGO_INPUT)
	@echo "=== PGO pass 2.5: merging profile data ==="
	$(LLVM_PROFDATA) merge -output=$(PGO_DIR)/default.profdata $(PGO_DIR)/*.profraw
	@echo "=== PGO pass 3: rebuilding with profile data ==="
	$(CC) $(CFLAGS) -fprofile-use=$(PGO_DIR) \
		$(SRCS) \
		$(LDFLAGS) $(LDLIBS) -fprofile-use=$(PGO_DIR) \
		-o $(TARGET)
	@echo "=== PGO build complete: $(TARGET) ==="

# ── Callgrind (Valgrind) — Linux only ────────────────────────────
#
# Not available on macOS — use profile-instruments instead.

CALLGRIND_DIR    = $(BUILD_DIR)/callgrind
CALLGRIND_TARGET = $(CALLGRIND_DIR)/sophie-germain-prime-finder
CALLGRIND_OUT    = $(CALLGRIND_DIR)/callgrind.out

# Valgrind's JIT (VEX) does not support all instruction sets, so
# -march=native can emit instructions it cannot translate (e.g.
# AVX-512).  Strip it for Callgrind builds; everything else from
# CFLAGS carries through unchanged.
CALLGRIND_CFLAGS = $(filter-out -march=native,$(CFLAGS)) -g

ifeq ($(UNAME), Darwin)
profile-callgrind profile-callgrind-cache:
	@echo "Error: Callgrind (Valgrind) is not supported on macOS." >&2
	@echo "Use 'make profile-instruments' or 'make profile-llvm' instead." >&2
	@exit 1
else
profile-callgrind:
	@echo "=== Callgrind: building with project flags + debug symbols ==="
	mkdir -p $(CALLGRIND_DIR)
	$(CC) $(CALLGRIND_CFLAGS) $(SRCS) $(LDFLAGS) $(LDLIBS) -o $(CALLGRIND_TARGET)
	@echo "=== Callgrind: profiling with input $(PROFILE_INPUT) ==="
	valgrind --tool=callgrind \
		--callgrind-out-file=$(CALLGRIND_OUT) \
		$(CALLGRIND_TARGET) $(PROFILE_INPUT)
	@echo ""
	@echo "=== Callgrind: annotated source ==="
	callgrind_annotate $(CALLGRIND_OUT) --auto=yes
	@echo ""
	@echo "Raw data: $(CALLGRIND_OUT)"
	@echo "Re-annotate with: callgrind_annotate $(CALLGRIND_OUT) --auto=yes"

profile-callgrind-cache:
	@echo "=== Callgrind (cache sim): building with project flags + debug symbols ==="
	mkdir -p $(CALLGRIND_DIR)
	$(CC) $(CALLGRIND_CFLAGS) $(SRCS) $(LDFLAGS) $(LDLIBS) -o $(CALLGRIND_TARGET)
	@echo "=== Callgrind (cache sim): profiling with input $(PROFILE_INPUT) ==="
	valgrind --tool=callgrind \
		--cache-sim=yes \
		--callgrind-out-file=$(CALLGRIND_OUT) \
		$(CALLGRIND_TARGET) $(PROFILE_INPUT)
	@echo ""
	@echo "=== Callgrind (cache sim): annotated source ==="
	callgrind_annotate $(CALLGRIND_OUT) --auto=yes
	@echo ""
	@echo "Raw data: $(CALLGRIND_OUT)"
endif

# ── Instruments (xctrace) — macOS only ───────────────────────────
#
# Apple's native profiler, driven from the command line via xctrace.
# Uses hardware sampling with very low overhead (~2-5%) and produces
# a .trace bundle for interactive analysis in Instruments.app.
#
# The Time Profiler template gives per-function CPU cost, call trees,
# and source-level annotation — comparable to Callgrind but with
# hardware-accurate timing rather than instruction-level simulation.
#
# Not available on Linux — use profile-callgrind instead.

INSTRUMENTS_DIR    = $(BUILD_DIR)/instruments
INSTRUMENTS_TARGET = $(INSTRUMENTS_DIR)/sophie-germain-prime-finder
INSTRUMENTS_TRACE  = $(INSTRUMENTS_DIR)/profile.trace

ifeq ($(UNAME), Darwin)
profile-instruments:
	@echo "=== Instruments: building with project flags + debug symbols ==="
	mkdir -p $(INSTRUMENTS_DIR)
	$(CC) $(CFLAGS) -g $(SRCS) $(LDFLAGS) $(LDLIBS) -o $(INSTRUMENTS_TARGET)
	@echo "=== Instruments: profiling with input $(PROFILE_INPUT) ==="
	rm -rf $(INSTRUMENTS_TRACE)
	xcrun xctrace record \
		--template 'Time Profiler' \
		--output $(INSTRUMENTS_TRACE) \
		--launch -- $(INSTRUMENTS_TARGET) $(PROFILE_INPUT)
	@echo ""
	@echo "=== Instruments: profiling complete ==="
	@echo "Trace: $(INSTRUMENTS_TRACE)"
	@echo "Open with: open $(INSTRUMENTS_TRACE)"
else
profile-instruments:
	@echo "Error: Instruments (xctrace) is only available on macOS." >&2
	@echo "Use 'make profile-callgrind' or 'make profile-llvm' instead." >&2
	@exit 1
endif

# ── LLVM Source-Based Profiling ──────────────────────────────────
#
# Note: -fprofile-instr-generate conflicts with PGO's
# -fprofile-use, so this target cannot profile PGO-optimised code.
# Use Callgrind for that (see above).

LLVM_PROF_DIR    = $(BUILD_DIR)/llvm-prof
LLVM_PROF_TARGET = $(LLVM_PROF_DIR)/sophie-germain-prime-finder

profile-llvm:
	@echo "=== LLVM profile: building instrumented binary ==="
	mkdir -p $(LLVM_PROF_DIR)
	$(CC) $(CFLAGS) -g \
		-fprofile-instr-generate -fcoverage-mapping \
		$(SRCS) \
		$(LDFLAGS) $(LDLIBS) -fprofile-instr-generate \
		-o $(LLVM_PROF_TARGET)
	@echo "=== LLVM profile: profiling with input $(PROFILE_INPUT) ==="
	LLVM_PROFILE_FILE=$(LLVM_PROF_DIR)/default.profraw \
		$(LLVM_PROF_TARGET) $(PROFILE_INPUT)
	@echo "=== LLVM profile: merging profile data ==="
	$(LLVM_PROFDATA) merge \
		-output=$(LLVM_PROF_DIR)/default.profdata \
		$(LLVM_PROF_DIR)/default.profraw
	@echo ""
	@echo "=== LLVM profile: annotated source ==="
	$(LLVM_COV) show $(LLVM_PROF_TARGET) \
		-instr-profile=$(LLVM_PROF_DIR)/default.profdata \
		--show-line-counts-or-regions
	@echo ""
	@echo "=== LLVM profile: function summary ==="
	$(LLVM_COV) report $(LLVM_PROF_TARGET) \
		-instr-profile=$(LLVM_PROF_DIR)/default.profdata
	@echo ""
	@echo "Profile data: $(LLVM_PROF_DIR)/default.profdata"

# ── Benchmarking (hyperfine) ─────────────────────────────────────

BENCH_DIR   = benchmarks/results
BENCH_INPUT ?= 1000000000000000000
BENCH_COMMIT = $(shell git rev-parse --short HEAD)
BENCH_JSON   = $(BENCH_DIR)/$(BENCH_COMMIT).json

bench: $(TARGET)
	mkdir -p $(BENCH_DIR)
	hyperfine --warmup 3 --min-runs 10 \
		--export-json $(BENCH_JSON) \
		'$(TARGET) $(BENCH_INPUT)'
	@echo ""
	@echo "Results saved to $(BENCH_JSON)"
	@echo "Attach to commit with: make bench-note"

bench-note:
	@if [ ! -f $(BENCH_JSON) ]; then \
		echo "Error: no results for $(BENCH_COMMIT). Run 'make bench' first." >&2; \
		exit 1; \
	fi
	git notes --ref=benchmarks add -f \
		-m "$$(cat $(BENCH_JSON))" HEAD
	@echo "Git note attached to $(BENCH_COMMIT)"
	@echo "View with: git notes --ref=benchmarks show $(BENCH_COMMIT)"

clean:
	rm -rf $(BUILD_DIR)/

-include $(OBJS:.o=.d)

.PHONY: pgo profile-callgrind profile-callgrind-cache profile-instruments profile-llvm clean
