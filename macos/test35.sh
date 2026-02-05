#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================
RESULTS_LOG="$HOME/ufd_results.log"
RESERVE_GB=10
TEST_SRC="$HOME/ufd_src"
READBACK_DST="$HOME/ufd_readback"

# =========================
# UTIL: log
# =========================
log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$RESULTS_LOG"
}

# =========================
# UTIL: timing
# =========================
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

# =========================
# STEP A: detect UFD
# =========================
detect_ufd() {
  disk=$(diskutil list external physical | awk '/\/dev\/disk/{print $1; exit}')
  disk=${disk#/dev/}
  [[ -z "$disk" ]] && { log "ERROR: No external UFD detected"; exit 1; }
  log "Detected UFD: $disk"
}

# =========================
# STEP A: mount + find mount point
# =========================
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

  [[ -z "$mount_point" ]] && { log "ERROR: Unable to determine mount point"; exit 1; }
  log "Mounted at: $mount_point"
}

# =========================
# STEP B: prepare test data
# =========================
prepare_test_data() {
  mkdir -p "$TEST_SRC"

  ufd_free_bytes=$(df -k "$mount_point" | tail -1 | awk '{print $4 * 1024}')
  host_free_bytes=$(df -k "$HOME" | tail -1 | awk '{print $4 * 1024}')

  reserve_bytes=$((RESERVE_GB * 1024 * 1024 * 1024))
  host_usable_bytes=$((host_free_bytes - reserve_bytes))

  (( host_usable_bytes <= 0 )) && {
    log "ERROR: Host free space < ${RESERVE_GB}GB reserve"
    exit 1
  }

  if (( ufd_free_bytes <= host_usable_bytes )); then
    test_bytes=$ufd_free_bytes
    reason="UFD limited"
  else
    test_bytes=$host_usable_bytes
    reason="Host limited (reserve ${RESERVE_GB}GB)"
  fi

  test_mb=$((test_bytes / 1024 / 1024))

  log "Prepare test data:"
  log "  UFD free  : $((ufd_free_bytes / 1024 / 1024 / 1024)) GB"
  log "  Host free : $((host_free_bytes / 1024 / 1024 / 1024)) GB"
  log "  Test size : $((test_mb / 1024)) GB ($reason)"

  dd if=/dev/zero of="$TEST_SRC/bigfile.bin" bs=1M count="$test_mb" status=progress
}

# =========================
# STEP B+C: WRITE test
# =========================
write_test() {
  log "WRITE test started"
  start=$(now)
  cp -R "$TEST_SRC" "$mount_point/"
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$TEST_SRC" | awk '{print $1/1024/1024}')
  write_speed=$(python3 - <<EOF
print(round($size_gb / $duration, 1))
EOF
)

  log "WRITE completed: ${write_speed} MB/s (time ${duration}s)"
}

# =========================
# STEP D+F: full + negative test
# =========================
verify_full_and_negative() {
  free_kb=$(df -k "$mount_point" | tail -1 | awk '{print $4}')
  [[ "$free_kb" -eq 0 ]] && log "Drive full check: OK"

  log "Negative copy test (expect failure)"
  set +e
  dd if=/dev/zero of="$mount_point/overflow.bin" bs=1M count=2048 2>>"$RESULTS_LOG"
  rc=$?
  set -e

  [[ "$rc" -eq 0 ]] && { log "ERROR: Overflow copy succeeded"; exit 1; }
  log "Negative copy test: PASS"
}

# =========================
# STEP G+H: READ test
# =========================
read_test() {
  mkdir -p "$READBACK_DST"
  log "READ test started"

  start=$(now)
  cp -R "$mount_point/ufd_src" "$READBACK_DST/"
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$mount_point/ufd_src" | awk '{print $1/1024/1024}')
  read_speed=$(python3 - <<EOF
print(round($size_gb / $duration, 1))
EOF
)

  log "READ completed: ${read_speed} MB/s (time ${duration}s)"
}

# =========================
# STEP K: reconnect detection
# =========================
reconnect_test() {
  log "Reconnect detection test"
  diskutil eject "$disk"

  start=$(now)
  while ! diskutil list | grep -q "$disk"; do sleep 0.2; done
  end=$(now)

  detect_time=$(calc_duration "$start" "$end")
  log "Reconnect detect time: ${detect_time}s"
}

# =========================
# STEP L: delete test
# =========================
delete_test() {
  log "Delete test started"
  start=$(now)
  rm -rf "$mount_point/ufd_src"
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  log "Delete completed in ${duration}s"
}

# =========================
# MAIN
# =========================
main() {
  log "===== UFD Marketing Workload START ====="
  detect_ufd
  mount_ufd
  prepare_test_data
  write_test
  verify_full_and_negative
  read_test
  reconnect_test
  delete_test
  log "===== UFD Marketing Workload END ====="
}

main "$@"
