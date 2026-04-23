#include <moonbit.h>
#include <stdio.h>
#include <stdint.h>

void trpg_write_stdout(moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  if (len > 0) {
    fwrite(bytes, 1, len, stdout);
  }
  fflush(stdout);
}

void trpg_write_stderr(moonbit_bytes_t bytes) {
  int32_t len = Moonbit_array_length(bytes);
  if (len > 0) {
    fwrite(bytes, 1, len, stderr);
  }
  fflush(stderr);
}
