#!/usr/bin/env bash
#!/bin/bash
set -euo pipefail
set +x
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

RESERVE_GB=10
UFD_CAP_GB=100
SEQ_SRC="$HOME/ufd_src"
MIX_SRC="$HOME/ufd_mix_src"
READBACK_DST="$HOME/ufd_readback"

LOG_DIR="$HOME/SSD_Format_Benchmark"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_LOG="${LOG_DIR}/OS3538MAC_log_${TIMESTAMP}.log"


if command -v python3 >/dev/null 2>&1; then
  TIMING_MODE="python"
else
  TIMING_MODE="int"
fi

# ==========================================================
# UTILITIES
# ==========================================================


log_message() {
    local message=$1
    local color="${2:-$NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$RESULTS_LOG"
    echo -e "${color}${message}${NC}"
}

now() {
  if [[ "$TIMING_MODE" == "python" ]]; then
    python3 - <<EOF
import time
print(time.time())
EOF
  else
    date +%s
  fi
}

calc_duration() {
  if [[ "$TIMING_MODE" == "python" ]]; then
    python3 -c "print(round($2 - $1, 1))"
  else
    echo $(( $2 - $1 ))
  fi
}

calc_speed() {
  if [[ "$TIMING_MODE" == "python" ]]; then
    python3 -c "print(round($1 / $2, 1))"
  else
    command -v bc >/dev/null 2>&1 || { echo "N/A"; return; }
    echo "scale=1; $1 / $2" | bc
  fi
}

# ==========================================================
# STEP A: Detect & mount UFD
# ==========================================================
detect_ufd() {
  disk=$(diskutil list external physical | awk '/\/dev\/disk/{print $1; exit}')
  disk=${disk#/dev/}
  [[ -z "$disk" ]] && { log_message "ERROR: No UFD detected"; exit 1; }
  log_message "Detected UFD: $disk"  "$GREEN"
}

mount_ufd() {
  diskutil mountDisk "$disk" >/dev/null 2>&1 || true
  mount_point=""
  for i in {1..5}; do
    slice="${disk}s$i"
     if ! info=$(diskutil info "$slice" 2>/dev/null); then
        continue
      fi
      mp=$(echo "$info" | awk -F': ' '/Mount Point/ {print $2}' | xargs)
    if [[ -n "$mp" && -d "$mp" ]]; then
      mount_point="${mp% [0-9]*}"
      break
    fi
  done

  [[ -z "$mount_point" ]] && { log_message "ERROR: Mount point not found" "$RED"; exit 1; }
  log_message "Mounted at: $mount_point" "$GREEN"
}

# ==========================================================
# STEP B: Prepare sequential test data (adaptive size)
# ==========================================================
get_effective_test_bytes() {
  UFD_CAP_BYTES=$((UFD_CAP_GB * 1024 * 1024 * 1024))

  actual_ufd_free_bytes=$(df -k "$mount_point" | awk 'END {print $4 * 1024}')

  if (( actual_ufd_free_bytes > UFD_CAP_BYTES )); then
    ufd_free_bytes=$UFD_CAP_BYTES
    ufd_reason="UFD capped at ${UFD_CAP_GB}GB"
  else
    ufd_free_bytes=$actual_ufd_free_bytes
    ufd_reason="UFD actual free space"
  fi

  host_free_bytes=$(df -k "$HOME" | awk 'END {print $4 * 1024}')
  reserve_bytes=$((RESERVE_GB * 1024 * 1024 * 1024))
  host_usable_bytes=$((host_free_bytes - reserve_bytes))

  (( host_usable_bytes <= 0 )) && {
    log_message "ERROR: Host free space < ${RESERVE_GB}GB" "$RED" 
    exit 1
  }

  if (( ufd_free_bytes <= host_usable_bytes )); then
    echo "$ufd_free_bytes|$ufd_reason"
  else
    echo "$host_usable_bytes|Host limited (reserve ${RESERVE_GB}GB)"
  fi
}


prepare_seq_data() {

  mkdir -p "$SEQ_SRC"
  IFS='|' read -r test_bytes reason <<< "$(get_effective_test_bytes)"
  test_mb=$((test_bytes / 1024 / 1024))

  log_message "SEQ test size: $((test_mb / 1024)) GB ($reason)" "$BLUE" 
  dd if=/dev/zero of="$SEQ_SRC/bigfile.bin" bs=1M count="$test_mb" status=progress
  expected_bytes=$((test_mb * 1024 * 1024))
  actual_bytes=$(stat -f %z "$SEQ_SRC/bigfile.bin" 2>/dev/null)

  if [[ "$actual_bytes" -ne "$expected_bytes" ]]; then
    log_message "ERROR: File size mismatch" "$RED" 
    log_message "Expected: $expected_bytes bytes"
    log_message "Actual:   $actual_bytes bytes"
    exit 1
  fi
}

# ==========================================================
# STEP B+C: Sequential WRITE test
# ==========================================================
seq_write_test() {
  log_message "Sequential WRITE test start" "$BLUE"

  rm -rf "$UFD_DST"
  mkdir -p "$UFD_DST"

  start=$(now)
  cp -R "$SEQ_SRC/." "$UFD_DST/"
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$SEQ_SRC" | awk '{print $1/1024/1024}')
  speed=$(calc_speed "$size_gb" "$duration")

  log_message "SEQ WRITE: ${speed} MB/s (${duration}s)" "$YELLOW"
}

# ==========================================================
# STEP D+F: Full + negative copy
# ==========================================================
verify_limit_and_negative() {
  # --- verify written size ---
  written_bytes=$(du -sk "$UFD_DST" | awk '{print $1 * 1024}')
  IFS='|' read -r expected_bytes _ <<< "$(get_effective_test_bytes)"

  if (( written_bytes < expected_bytes * 95 / 100 )); then
    log_message "ERROR: Written data size too small" "$RED" 
    log_message "Expected ~${expected_bytes} bytes, got ${written_bytes}"
    exit 1
  fi

  log_message "Data size verification: OK (capped workload)" "$GREEN"

  # --- negative copy test ---
  log_message "Negative copy test (expect failure due to test limit)" "$BLUE" 

  set +e
  dd if=/dev/zero of="$mount_point/overflow.bin" bs=1M count=1024 2>>"$RESULTS_LOG"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    log_message "ERROR: Overflow copy succeeded (unexpected)" "$RED"
    exit 1
  fi

  log_message "Negative copy: PASS" "$GREEN"
}

# ==========================================================
# STEP G+H: Sequential READ test
# ==========================================================
seq_read_test() {
  mkdir -p "$READBACK_DST"
  log_message "Sequential READ test start" "$BLUE" 

  start=$(now)
  cp -R "$UFD_DST/." "$READBACK_DST/"
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$mount_point/ufd_seq_src" | awk '{print $1/1024/1024}')
  speed=$(calc_speed "$size_gb" "$duration")

  log_message "SEQ READ: ${speed} MB/s (${duration}s)" "$YELLOW"
}

# ==========================================================
# STEP K: Reconnect detection
# ==========================================================
reconnect_test() {
  log_message "===== MANUAL TEST REQUIRED ====="
  log_message "Reconnect detection test" "$YELLOW" 
  log_message "1) Safely eject the UFD now" "$YELLOW" 
  log_message "2) Physically remove the UFD" "$YELLOW" 
  log_message "3) Reconnect the UFD to the same port" "$YELLOW" 
  log_message "4) Measure and record the detection time manually" "$YELLOW" 
  log_message "5) Verify the drive appears in Finder / diskutil list" "$YELLOW" 
  log_message "================================"

  echo
  read -p "Press ENTER after reconnect test is completed..."
}


# ==========================================================
# STEP L: Delete test
# ==========================================================
delete_test() {
  local dirrm="$1"
  log_message "Delete test start"
  start=$(now)
  rm -rf "$dirrm"
  end=$(now)
  duration=$(calc_duration "$start" "$end")
  log_message "Delete completed in ${duration}s" "$CYAN"
}

# ==========================================================
# SUB-TEST: Parallel 50% + Self R/W
# ==========================================================
prepare_mixed_50pct() {
  mkdir -p "$MIX_SRC"
  mkdir -p "$UFD_DST"
  mkdir -p "$UFD_DSTCP"

  IFS='|' read -r base_bytes base_reason <<< "$(get_effective_test_bytes)"

  mix_bytes=$((base_bytes / 2))
  mix_mb=$((mix_bytes / 1024 / 1024))

  log_message "Mixed workload size: $((mix_mb / 1024)) GB (50% of $base_reason)" "$BLUE" 

  # 80% large, 20% small
  large_mb=$((mix_mb * 8 / 10))
  small_files=2000

  dd if=/dev/zero of="$MIX_SRC/large.bin" bs=1M count="$large_mb" status=none

  mkdir -p "$MIX_SRC/small"
  for i in $(seq 1 $small_files); do
    dd if=/dev/zero of="$MIX_SRC/small/file_$i.bin" bs=64K count=1 status=none
  done
}

parallel_write_50pct() {
  log_message "Parallel WRITE (2 instances, 50%)"
  start=$(now)
  cp -R "$MIX_SRC/large.bin" "$mount_point/" &
  cp -R "$MIX_SRC/small" "$mount_point/" &
  wait
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$MIX_SRC" | awk '{print $1/1024/1024}')
  speed=$(calc_speed "$size_gb" "$duration")

  log_message "PAR WRITE: ${speed} MB/s (${duration}s)" "$YELLOW"
}

self_rw_parallel() {
  log_message "Self R/W (UFD→UFD, 2 instances)"
  start=$(now)
  cp -R "$mount_point/large.bin" "$UFD_DSTCP/" &
  cp -R "$mount_point/small" "$UFD_DSTCP/" &
  wait
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_gb=$(du -sk "$MIX_SRC" | awk '{print $1/1024/1024}')
  speed=$(calc_speed "$size_gb" "$duration")

  log_message "SELF R/W: ${speed} MB/s (${duration}s)" "$YELLOW"
}

compare_internal_data() {
  log_message "Comparing self-copied data"
  cmp "$mount_point/large.bin" "$UFD_DSTCP/large.bin"
  diff -qr "$mount_point/small" "$UFD_DSTCP/small"
  log_message "Data compare: PASS"
}

Speedtest() {
    local test_file
    local size_mb=1024
    local free_mb
    local write_out write_speed
    local read_out read_speed
    [ -d "$mount_point" ] || { echo "N/A,N/A"; return 0; }

    free_mb=$(df -m "$mount_point" | tail -1 | awk '{print $4}')
    if (( free_mb < size_mb )); then
        echo "DISK_FULL,DISK_FULL"
        return 0
    fi

    export LC_ALL=C
    test_file="$mount_point/test.bin"
    # ---------- WRITE ----------
    sync
    write_out=$(dd if=/dev/zero of="$test_file" bs=1m count="$size_mb" conv=sync 2>&1 || true)
    sync
    write_speed=$(echo "$write_out" | awk '
        /[0-9.]+\s*GB\/s/ {print $1 * 1024; exit}
        /[0-9.]+\s*MB\/s/ {print $1; exit}
        /\([0-9]+ bytes\/sec\)/ {match($0,/\(([0-9]+)/); print substr($0,RSTART+1,RLENGTH-1)/1048576; exit}
    ' | tail -n 1)

    # ---------- READ ----------
    sleep 2
    read_out=$(dd if="$test_file" of=/dev/null bs=1m 2>&1 || true)
    read_speed=$(echo "$read_out" | awk '
        /[0-9.]+\s*GB\/s/ {print $1 * 1024; exit}
        /[0-9.]+\s*MB\/s/ {print $1; exit}
        /\([0-9]+ bytes\/sec\)/ {match($0,/\(([0-9]+)/); print substr($0,RSTART+1,RLENGTH-1)/1048576; exit}
    ' | tail -n 1)

    [ -z "$write_speed" ] && write_speed="0"
    [ -z "$read_speed" ] && read_speed="0"

    rm -f "$test_file"

    echo "${read_speed},${write_speed}"
}

# ==========================================================
# MAIN
# ==========================================================
main() {
  log_message "===== UFD Marketing Workload START =====" "$MAGENTA"

  detect_ufd
  mount_ufd
  UFD_DST="$mount_point/ufd_dst"
  UFD_DSTCP="$mount_point/ufd_dst2"
  # Parallel + Self R/W sub-test
  log_message "===== Parallel + Self R/W Sub-Test START ====="
  prepare_mixed_50pct
  # Run speedtest before
  log_message "speed test before write ... waiting..." "$BLUE" 
  IFS=',' read readspeed writespeed < <(Speedtest "$mount_point")
  log_message"(before) read speed: ${readspeed}, write speed: ${writespeed}" "$YELLOW" 

  parallel_write_50pct
  
  # Run speedtest after
  log_message "speed test after write ... waiting..." "$BLUE" 
  IFS=',' read readspeed writespeed < <(Speedtest "$mount_point")
  log_message"(after) read speed: ${readspeed}, write speed: ${writespeed}" "$YELLOW" 

  self_rw_parallel
  compare_internal_data
  delete_test "$MIX_SRC"
  delete_test "$UFD_DST"
  delete_test "$UFD_DSTCP"


  # Sequential workload
  prepare_seq_data

  # Run speedtest before
  log_message "speed test before write ... waiting..." "$BLUE" 
  IFS=',' read readspeed writespeed < <(Speedtest "$mount_point")
  log_message "(before) read speed: ${readspeed}, write speed: ${writespeed}" "$YELLOW" 

  seq_write_test

  # Run speedtest after
  log_message "speed test after write ... waiting..." "$BLUE" 
  IFS=',' read readspeed writespeed < <(Speedtest "$mount_point")
  log_message "$GREEN" "(after) read speed: ${readspeed}, write speed: ${writespeed}"

  verify_full_and_negative
  seq_read_test
  reconnect_test
  delete_test "$UFD_DST"
  delete_test "$SEQ_SRC"

  log_message "===== Parallel + Self R/W Sub-Test END ====="
  log_message "===== UFD Marketing Workload END =====" "$MAGENTA"

}

main "$@"
