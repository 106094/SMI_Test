#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# CONFIG
# ==========================================================
RESULTS_LOG="$HOME/ufd_results.log"
RESERVE_GB=10

SEQ_SRC="$HOME/ufd_seq_src"
MIX_SRC="$HOME/ufd_mix_src"
READBACK_DST="$HOME/ufd_readback"

# ==========================================================
# UTILITIES
# ==========================================================
log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$RESULTS_LOG"
}

now() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<EOF
import time
print(time.time())
EOF
  else
    date +%s
  fi
}

calc_duration() {
  python3 - <<EOF
print(round($2 - $1, 1))
EOF
}

calc_speed() {
  python3 - <<EOF
print(round($1 / $2, 1))
EOF
}

# ==========================================================
# STEP A: Detect & mount UFD
# ==========================================================
detect_ufd() {
  disk=$(diskutil list external physical | awk '/\/dev\/disk/{print $1; exit}')
  disk=${disk#/dev/}
  [[ -z "$disk" ]] && { log "ERROR: No UFD detected"; exit 1; }
  log "Detected UFD: $disk"
}

mount_ufd() {
  diskutil mountDisk "$disk" >/dev/null 2>&1 || true

  mount_point=""
  for i in {1..5}; do
    slice="${disk}s$i"
    mp=$(diskutil info -plist "$slice" 2>/dev/null \
         | plutil -extract MountPoint raw - 2>/dev/null)
    if [[ -n "$mp" && -d "$mp" ]]; then
      mount_point="${mp% [0-9]*}"
      break
    fi
  done

  [[ -z "$mount_point" ]] && { log "ERROR: Mount point not found"; exit 1; }
  log "Mounted at: $mount_point"
}

# ==========================================================
# STEP B: Prepare sequential test data (adaptive size)
# ==========================================================
prepare_seq_data() {
  mkdir -p "$SEQ_SRC"

  ufd_free_bytes=$(df -k "$mount_point" | tail -1 | awk '{print $4 * 1024}')
  host_free_bytes=$(df -k "$HOME" | tail -1 | awk '{print $4 * 1024}')
  reserve_bytes=$((RESERVE_GB * 1024 * 1024 * 1024))
  host_usable_bytes=$((host_free_bytes - reserve_bytes))

  (( host_usable_bytes <= 0 )) && {
    log "ERROR: Host free space < ${RESERVE_GB}GB"
    exit 1
  }

  if (( ufd_free_bytes <= host_usable_bytes )); then
    test_bytes=$ufd_free_bytes
    reason="UFD limited"
  else
    test_bytes=$host_usable_bytes
    reason="Host limited"
  fi

  test_mb=$((test_bytes / 1024 / 1024))

  log "SEQ test size: $((test_mb / 1024)) GB ($reason)"
  dd if=/dev/zero of="$SEQ_SRC/bigfile.bin" bs=1M count="$test_mb" status=progress
}

# ==========================================================
# STEP B+C: Sequential WRITE test
# ==========================================================
seq_write_test() {
  log "Sequential WRITE test start"
  start=$(now)
  cp -R "$SEQ_SRC" "$mount_point/"
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$SEQ_SRC" | awk '{print $1/1024/1024}')
  speed=$(calc_speed "$size_gb" "$duration")

  log "SEQ WRITE: ${speed} MB/s (${duration}s)"
}

# ==========================================================
# STEP D+F: Full + negative copy
# ==========================================================
verify_full_and_negative() {
  free_kb=$(df -k "$mount_point" | tail -1 | awk '{print $4}')
  [[ "$free_kb" -eq 0 ]] && log "Drive full check: OK"

  log "Negative copy test (expect failure)"
  set +e
  dd if=/dev/zero of="$mount_point/overflow.bin" bs=1M count=2048 2>>"$RESULTS_LOG"
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] && { log "ERROR: Overflow copy succeeded"; exit 1; }
  log "Negative copy: PASS"
}

# ==========================================================
# STEP G+H: Sequential READ test
# ==========================================================
seq_read_test() {
  mkdir -p "$READBACK_DST"
  log "Sequential READ test start"

  start=$(now)
  cp -R "$mount_point/ufd_seq_src" "$READBACK_DST/"
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$mount_point/ufd_seq_src" | awk '{print $1/1024/1024}')
  speed=$(calc_speed "$size_gb" "$duration")

  log "SEQ READ: ${speed} MB/s (${duration}s)"
}

# ==========================================================
# STEP K: Reconnect detection
# ==========================================================
reconnect_test() {
  log "Reconnect detection test"
  diskutil eject "$disk"

  start=$(now)
  while ! diskutil list | grep -q "$disk"; do sleep 0.2; done
  end=$(now)

  detect_time=$(calc_duration "$start" "$end")
  log "Reconnect detect time: ${detect_time}s"
}

# ==========================================================
# STEP L: Delete test
# ==========================================================
delete_test() {
  log "Delete test start"
  start=$(now)
  rm -rf "$mount_point/ufd_seq_src"
  end=$(now)
  duration=$(calc_duration "$start" "$end")
  log "Delete completed in ${duration}s"
}

# ==========================================================
# SUB-TEST: Parallel 50% + Self R/W
# ==========================================================
prepare_mixed_50pct() {
  mkdir -p "$MIX_SRC"

  ufd_free_bytes=$(df -k "$mount_point" | tail -1 | awk '{print $4 * 1024}')
  half_bytes=$((ufd_free_bytes / 2))
  half_mb=$((half_bytes / 1024 / 1024))

  log "Preparing 50% mixed data: $((half_mb / 1024)) GB"

  dd if=/dev/zero of="$MIX_SRC/large.bin" bs=1M count=$((half_mb * 8 / 10)) status=none
  mkdir -p "$MIX_SRC/small"
  for i in {1..2000}; do
    dd if=/dev/zero of="$MIX_SRC/small/file_$i.bin" bs=64K count=1 status=none
  done
}

parallel_write_50pct() {
  log "Parallel WRITE (2 instances, 50%)"
  start=$(now)
  cp -R "$MIX_SRC/large.bin" "$mount_point/" &
  cp -R "$MIX_SRC/small" "$mount_point/" &
  wait
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$MIX_SRC" | awk '{print $1/1024/1024}')
  speed=$(calc_speed "$size_gb" "$duration")

  log "PAR WRITE: ${speed} MB/s (${duration}s)"
}

self_rw_parallel() {
  INTERNAL_DST="$mount_point/self_copy"
  mkdir -p "$INTERNAL_DST"

  log "Self R/W (UFD→UFD, 2 instances)"
  start=$(now)
  cp -R "$mount_point/large.bin" "$INTERNAL_DST/" &
  cp -R "$mount_point/small" "$INTERNAL_DST/" &
  wait
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$MIX_SRC" | awk '{print $1/1024/1024}')
  speed=$(calc_speed "$size_gb" "$duration")

  log "SELF R/W: ${speed} MB/s (${duration}s)"
}

compare_internal_data() {
  log "Comparing self-copied data"
  cmp "$mount_point/large.bin" "$mount_point/self_copy/large.bin"
  diff -qr "$mount_point/small" "$mount_point/self_copy/small"
  log "Data compare: PASS"
}

# ==========================================================
# MAIN
# ==========================================================
main() {
  log "===== UFD Marketing Workload START ====="

  detect_ufd
  mount_ufd

  # Sequential workload
  prepare_seq_data
  seq_write_test
  verify_full_and_negative
  seq_read_test
  reconnect_test
  delete_test

  # Parallel + Self R/W sub-test
  log "===== Parallel + Self R/W Sub-Test START ====="
  prepare_mixed_50pct
  parallel_write_50pct
  self_rw_parallel
  compare_internal_data
  log "===== Parallel + Self R/W Sub-Test END ====="

  log "===== UFD Marketing Workload END ====="
}

main "$@"
