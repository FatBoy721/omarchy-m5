// SPDX-License-Identifier: MIT
// wfi-check: per-CPU check that user FP/SIMD and callee-saved registers survive
// sleeps long enough for the CPU to idle (WFI). One thread per online CPU,
// each pinned; every iteration loads patterns, sleeps via a raw nanosleep
// syscall, and compares. Exit 0 = all intact.
// Build: aarch64-linux-gnu-gcc -O2 -static -pthread -o wfi-check wfi-check.c
#define _GNU_SOURCE
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>

static int iterations = 2000;
static long sleep_ns = 1000000;

struct state {
	uint64_t v[64];  /* v0..v31, 2 x u64 each, offset 0 */
	uint64_t x[10];  /* x19..x28, offset 512 */
};

static void run_once(const struct state *in, struct state *out, const struct timespec *ts)
{
	register long x0 asm("x0") = (long)ts;
	register long x1 asm("x1") = 0;
	register long x8 asm("x8") = SYS_nanosleep;
	register const struct state *pin asm("x9") = in;
	register struct state *pout asm("x10") = out;

	asm volatile(
		"ldp q0, q1, [x9, #0]\n ldp q2, q3, [x9, #32]\n"
		"ldp q4, q5, [x9, #64]\n ldp q6, q7, [x9, #96]\n"
		"ldp q8, q9, [x9, #128]\n ldp q10, q11, [x9, #160]\n"
		"ldp q12, q13, [x9, #192]\n ldp q14, q15, [x9, #224]\n"
		"ldp q16, q17, [x9, #256]\n ldp q18, q19, [x9, #288]\n"
		"ldp q20, q21, [x9, #320]\n ldp q22, q23, [x9, #352]\n"
		"ldp q24, q25, [x9, #384]\n ldp q26, q27, [x9, #416]\n"
		"ldp q28, q29, [x9, #448]\n ldp q30, q31, [x9, #480]\n"
		"add x11, x9, #512\n"
		"ldp x19, x20, [x11, #0]\n ldp x21, x22, [x11, #16]\n"
		"ldp x23, x24, [x11, #32]\n ldp x25, x26, [x11, #48]\n"
		"ldp x27, x28, [x11, #64]\n"
		"svc #0\n"
		"stp q0, q1, [x10, #0]\n stp q2, q3, [x10, #32]\n"
		"stp q4, q5, [x10, #64]\n stp q6, q7, [x10, #96]\n"
		"stp q8, q9, [x10, #128]\n stp q10, q11, [x10, #160]\n"
		"stp q12, q13, [x10, #192]\n stp q14, q15, [x10, #224]\n"
		"stp q16, q17, [x10, #256]\n stp q18, q19, [x10, #288]\n"
		"stp q20, q21, [x10, #320]\n stp q22, q23, [x10, #352]\n"
		"stp q24, q25, [x10, #384]\n stp q26, q27, [x10, #416]\n"
		"stp q28, q29, [x10, #448]\n stp q30, q31, [x10, #480]\n"
		"add x11, x10, #512\n"
		"stp x19, x20, [x11, #0]\n stp x21, x22, [x11, #16]\n"
		"stp x23, x24, [x11, #32]\n stp x25, x26, [x11, #48]\n"
		"stp x27, x28, [x11, #64]\n"
		: "+r"(x0), "+r"(x1)
		: "r"(x8), "r"(pin), "r"(pout)
		: "memory", "x11", "x19", "x20", "x21", "x22", "x23", "x24", "x25", "x26", "x27", "x28",
		  "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10", "v11", "v12", "v13",
		  "v14", "v15", "v16", "v17", "v18", "v19", "v20", "v21", "v22", "v23", "v24", "v25", "v26",
		  "v27", "v28", "v29", "v30", "v31");
}

struct worker {
	pthread_t thread;
	int cpu;
	long bad;
	long done;
	int ran_on_wrong_cpu;
};

static void *work(void *arg)
{
	struct worker *w = arg;
	cpu_set_t set;
	CPU_ZERO(&set);
	CPU_SET(w->cpu, &set);
	if (sched_setaffinity(0, sizeof(set), &set)) {
		perror("sched_setaffinity");
		w->bad = -1;
		return NULL;
	}
	struct timespec ts = { 0, sleep_ns };
	struct state in, out;
	for (int it = 0; it < iterations; it++) {
		for (int i = 0; i < 64; i++)
			in.v[i] = 0x5100000000000000ull | ((uint64_t)w->cpu << 40) | ((uint64_t)it << 8) | i;
		for (int i = 0; i < 10; i++)
			in.x[i] = 0xC500000000000000ull | ((uint64_t)w->cpu << 40) | ((uint64_t)it << 8) | i;
		memset(&out, 0, sizeof(out));
		run_once(&in, &out, &ts);
		if (memcmp(&in, &out, sizeof(in))) {
			if (w->bad < 5) {
				for (int i = 0; i < 64; i++)
					if (in.v[i] != out.v[i])
						fprintf(stderr, "cpu%d it%d v%d.d[%d]: %016llx != %016llx\n", w->cpu, it,
							i / 2, i % 2, (unsigned long long)out.v[i], (unsigned long long)in.v[i]);
				for (int i = 0; i < 10; i++)
					if (in.x[i] != out.x[i])
						fprintf(stderr, "cpu%d it%d x%d: %016llx != %016llx\n", w->cpu, it, 19 + i,
							(unsigned long long)out.x[i], (unsigned long long)in.x[i]);
			}
			w->bad++;
		}
		if (sched_getcpu() != w->cpu)
			w->ran_on_wrong_cpu = 1;
		w->done++;
	}
	return NULL;
}

int main(int argc, char **argv)
{
	if (argc > 1)
		iterations = atoi(argv[1]);
	if (argc > 2)
		sleep_ns = atol(argv[2]);
	cpu_set_t online;
	CPU_ZERO(&online);
	sched_getaffinity(0, sizeof(online), &online);
	struct worker *ws = calloc(CPU_SETSIZE, sizeof(*ws));
	int n = 0;
	for (int c = 0; c < CPU_SETSIZE; c++) {
		if (!CPU_ISSET(c, &online))
			continue;
		ws[n].cpu = c;
		pthread_create(&ws[n].thread, NULL, work, &ws[n]);
		n++;
	}
	long failed_cpus = 0;
	for (int i = 0; i < n; i++) {
		pthread_join(ws[i].thread, NULL);
		printf("cpu%-2d iterations=%ld corrupted=%ld%s\n", ws[i].cpu, ws[i].done, ws[i].bad,
		       ws[i].ran_on_wrong_cpu ? " (migrated!)" : "");
		failed_cpus += ws[i].bad ? 1 : 0;
	}
	printf("%s: %d CPUs, %d iterations each, %ld ns sleeps\n", failed_cpus ? "FAIL" : "PASS", n, iterations,
	       sleep_ns);
	return failed_cpus ? 1 : 0;
}
