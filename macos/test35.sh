#!/bin/bash
set -euo pipefail
#set -x #debug output
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
  local start=$1 end=$2
  if [[ "$TIMING_MODE" == "python" ]]; then
    python3 -c "print(round($end - $start, 1))"
  else
    echo $(( end - start ))
  fi
}

calc_speed() {
  local bytes=$1 secs=$2
  if [[ "$TIMING_MODE" == "python" ]]; then
    python3 -c "print(round($bytes / $secs, 1))"
  else
    command -v bc >/dev/null 2>&1 || { echo "N/A"; return; }
    echo "scale=1; $bytes / $secs" | bc
  fi
}

# ==========================================================
# STEP A: Detect & mount UFD
# ==========================================================
detect_ufd() {
  disk=$(diskutil list external physical | awk '/\/dev\/disk/{print $1; exit}')
  disk=${disk#/dev/}
  [[ -z "$disk" ]] && { log_message "ERROR: No UFD detected" "$RED"; exit 1; }
  log_message "Detected UFD: $disk"  "$GREEN"
}

mount_ufd() {
  diskutil unmountDisk "$disk" >/dev/null 2>&1 || true
  diskutil eraseDisk exFAT BENCH GPT "$disk" >/dev/null 2>&1
  diskutil mountDisk "$disk" >/dev/null 2>&1 || true
  mount_point=""
  for i in {1..5}; do
    slice="${disk}s$i"
     if ! info=$(diskutil info "$slice" 2>/dev/null); then
        continue
      fi
      content=$(echo "$info" | awk -F': ' '/Volume Name/ {print $2}' | xargs)
      mp=$(echo "$info" | awk -F': ' '/Mount Point/ {print $2}' | xargs)
    if [[ "$content" != "EFI" && -n "$mp" && -d "$mp" ]]; then
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
  dd if=/dev/zero of="$SEQ_SRC/bigfile.bin" bs=1m count="$test_mb" conv=fsync >/dev/null 2>&1 || true
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
  size_mb=$(du -sk "$UFD_DST" | awk '{print $1/1024}')
  speed=$(calc_speed "$size_mb" "$duration")

  log_message "SEQ WRITE: ${speed} MB/s (${duration}s)" "$YELLOW"
}

# ==========================================================
# STEP D+F: Full  (->100G) + negative copy
# ==========================================================

verify_file_size() {
  local src_path="$1"
  local dst_path="$2"
  local filename="bigfile.bin"

  local src_file="$src_path/$filename"
  local dst_file="$dst_path/$filename"

  # sanity checks
  [[ ! -f "$src_file" ]] && {
    log_message "ERROR: Missing source file $src_file" "$RED"
    return 1
  }

  [[ ! -f "$dst_file" ]] && {
    log_message "ERROR: Missing destination file $dst_file" "$RED"
    return 1
  }

  local expected written
  expected=$(stat -f %z "$src_file")
  written=$(stat -f %z "$dst_file")

  log_message "$filename in $src_path size: $expected bytes" "$YELLOW"
  log_message "$filename in $dst_path size: $written bytes" "$YELLOW"

  if (( expected != written )); then
    log_message "ERROR: Size mismatch (expected $expected, got $written)" "$RED"
    return 1
  else
    log_message "Size check: PASS" "$GREEN"
    return 0
  fi
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
  size_mb=$(du -sk "$UFD_DST" | awk '{print $1/1024}')
  speed=$(calc_speed "$size_mb" "$duration")
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
  start=$(now)
  rm -rf "$dirrm"
  end=$(now)
  duration=$(calc_duration "$start" "$end")
  log_message "Delete $dirrm completed in ${duration}s" "$CYAN"
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

  dd if=/dev/zero of="$MIX_SRC/large.bin" bs=1m count="$large_mb" conv=fsync >/dev/null 2>&1 || true

  mkdir -p "$MIX_SRC/small"
  for i in $(seq 1 $small_files); do
    dd if=/dev/zero of="$MIX_SRC/small/file_$i.bin" bs=64K count=1 status=none
  done
}

parallel_write_50pct() {
  log_message "Parallel WRITE (2 instances, 50%)"
  start=$(now)
  cp -R "$MIX_SRC/large.bin" "$UFD_DST/" &
  cp -R "$MIX_SRC/small" "$UFD_DST/" &
  wait
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_mb=$(du -sk "$MIX_SRC" | awk '{print $1/1024}')
  speed=$(calc_speed "$size_mb" "$duration")

  log_message "PAR WRITE: ${speed} MB/s (${duration}s)" "$YELLOW"
}

self_rw_parallel() {
  log_message "Self R/W (UFD→UFDCP, 2 instances)"
  start=$(now)
  cp -R "$UFD_DST/large.bin" "$UFD_DSTCP/" &
  cp -R "$UFD_DST/small" "$UFD_DSTCP/" &
  wait
  end=$(now)

  duration=$(calc_duration "$start" "$end")
  size_mb=$(du -sk "$MIX_SRC" | awk '{print $1/1024}')
  speed=$(calc_speed "$size_mb" "$duration")

  log_message "SELF R/W: ${speed} MB/s (${duration}s)" "$YELLOW"
}

compare_internal_data() {
  log_message "Comparing self-copied data"
  local fail=0

  cmp -s "$UFD_DST/large.bin" "$UFD_DSTCP/large.bin" || {
    log_message "Mismatch: large.bin" "$RED"
    fail=1
  }

  diff -qr "$UFD_DST/small" "$UFD_DSTCP/small" >/dev/null || {
    log_message "Mismatch: small directory" "$RED"
    fail=1
  }

  if [[ $fail -eq 0 ]]; then
    log_message "Data compare: PASS" "$GREEN"
    return 0
  else
    log_message "Data compare: FAIL" "$RED"
    return 1
  fi
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
  log_message "(before) read speed: ${readspeed}, write speed: ${writespeed}" "$YELLOW" 

  parallel_write_50pct
  
  # Run speedtest after
  log_message "speed test after write ... waiting..." "$BLUE" 
  IFS=',' read readspeed writespeed < <(Speedtest "$mount_point")
  log_message "(after) read speed: ${readspeed}, write speed: ${writespeed}" "$YELLOW" 

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
  log_message "(after) read speed: ${readspeed}, write speed: ${writespeed}" "$GREEN"

  verify_file_size "$SEQ_SRC" "$UFD_DST"
  delete_test "$SEQ_SRC"
  seq_read_test
  verify_file_size "$UFD_DST" "$READBACK_DST"
  reconnect_test
  delete_test "$SEQ_SRC"
  delete_test "$READBACK_DST"
  delete_test "$UFD_DST"

  log_message "===== Parallel + Self R/W Sub-Test END ====="
  log_message "===== UFD Marketing Workload END =====" "$MAGENTA"

}

main "$@"
