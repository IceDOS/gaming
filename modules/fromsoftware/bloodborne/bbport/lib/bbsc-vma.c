// BBSC checks each read against the runtime's mapping table, which lacks the game image (plain
// mmap), so it never reached the game state. Fall back to the kernel's mappings.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

typedef int (*VmaInfo)(uintptr_t address, int *prot, int *type, uintptr_t *end);

typedef struct {
  uintptr_t start, end;
  int prot;
} Range;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static Range *ranges;
static size_t count, capacity;
static uint64_t loaded_ns;
static unsigned long fallbacks;

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000u + (uint64_t)ts.tv_nsec;
}

static void reload(void) {
  FILE *maps = fopen("/proc/self/maps", "re");
  if (!maps) {
    return;
  }
  count = 0;
  char line[512];
  while (fgets(line, sizeof line, maps)) {
    unsigned long long start, end;
    char perms[5] = {0};
    if (sscanf(line, "%llx-%llx %4s", &start, &end, perms) != 3) {
      continue;
    }
    if (count == capacity) {
      size_t grown = capacity ? capacity * 2 : 4096;
      Range *bigger = realloc(ranges, grown * sizeof *ranges);
      if (!bigger) {
        break;
      }
      ranges = bigger;
      capacity = grown;
    }
    // PS4 protection bits, as the runtime table reports them.
    int prot = (perms[0] == 'r' ? 1 : 0) | (perms[1] == 'w' ? 2 : 0) | (perms[2] == 'x' ? 4 : 0);
    ranges[count++] = (Range){start, end, prot};
  }
  fclose(maps);
  loaded_ns = now_ns();
}

static const Range *find(uintptr_t address) {
  size_t lo = 0, hi = count;
  while (lo < hi) {
    size_t mid = (lo + hi) / 2;
    if (ranges[mid].end <= address) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo < count && ranges[lo].start <= address ? &ranges[lo] : NULL;
}

int bbport_bbsc_vma_info_v1(uintptr_t address, int *prot, int *type, uintptr_t *end) {
  static VmaInfo runtime;
  if (!runtime) {
    runtime = (VmaInfo)dlsym(RTLD_DEFAULT, "runtime_memory_vma_info");
  }
  if (runtime && runtime(address, prot, type, end)) {
    return 1;
  }
  if (address < 0x10000) {
    return 0;
  }
  pthread_mutex_lock(&lock);
  // A snapshot older than 200 ms is reloaded on a miss: mappings come and go while loading.
  const Range *range = find(address);
  if ((!range || !(range->prot & 1)) && now_ns() - loaded_ns > 200000000u) {
    reload();
    range = find(address);
  }
  int ok = range != NULL;
  if (ok) {
    *prot = range->prot;
    *type = -1;
    *end = range->end;
    if (fallbacks++ == 0) {
      fprintf(stderr, "BBSC memory: reads outside the runtime map allowed from /proc/self/maps "
                      "(first at %#lx)\n", (unsigned long)address);
    }
  }
  pthread_mutex_unlock(&lock);
  return ok;
}

// process_vm_readv cannot pin driver mappings (the new memory model's dma-buf game memory), so its
// table scan found nothing. /proc/self/mem reads go through the driver's access hook instead.
ssize_t bbsc_vm_readv_v1(pid_t pid, const struct iovec *local, unsigned long local_count,
                         const struct iovec *remote, unsigned long remote_count,
                         unsigned long flags) {
  ssize_t got = process_vm_readv(pid, local, local_count, remote, remote_count, flags);
  if (pid != getpid() || local_count != 1 || remote_count != 1) {
    return got;
  }
  size_t want = local->iov_len < remote->iov_len ? local->iov_len : remote->iov_len;
  if (got >= (ssize_t)want) {
    return got;
  }
  static int mem = -1;
  if (mem < 0) {
    int fd = open("/proc/self/mem", O_RDONLY | O_CLOEXEC);
    int expected = -1;
    if (fd >= 0 && !__atomic_compare_exchange_n(&mem, &expected, fd, 0, __ATOMIC_ACQ_REL,
                                                __ATOMIC_ACQUIRE)) {
      close(fd);
    }
    if (mem < 0) {
      return got;
    }
  }
  ssize_t read = pread(mem, local->iov_base, want, (off_t)(uintptr_t)remote->iov_base);
  return read > got ? read : got;
}
