#!/bin/bash

# macOS SSD Format Benchmark Script
# Tests all filesystem formats and partition schemes with filled SSD
# Measures format time for each combination

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_VERSION="1.0"
LOG_DIR="$HOME/SSD_Format_Benchmark"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_CSV="${LOG_DIR}/benchmark_results_${TIMESTAMP}.csv"
RESULTS_LOG="${LOG_DIR}/benchmark_log_${TIMESTAMP}.log"

# Create log directory
mkdir -p "$LOG_DIR"

# Initialize results array
declare -a RESULTS

print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}" | tee -a "$RESULTS_LOG"
}

print_header() {
    local message=$1
    echo "" | tee -a "$RESULTS_LOG"
    echo "=========================================" | tee -a "$RESULTS_LOG"
    echo "$message" | tee -a "$RESULTS_LOG"
    echo "=========================================" | tee -a "$RESULTS_LOG"
    echo "" | tee -a "$RESULTS_LOG"
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$RESULTS_LOG"
}

# Get disk identifier from volume path or disk number
get_disk_identifier() {
    local input=$1
    
    # Check if input is a disk number (e.g., "2" or "disk2")
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "disk${input}"
        return
    elif [[ "$input" =~ ^disk[0-9]+$ ]]; then
        echo "$input"
        return
    fi
    
    # Otherwise treat as volume path
    if [ -d "$input" ]; then
        diskutil info "$input" 2>/dev/null | grep "Part of Whole" | awk '{print $4}'
    else
        echo ""
    fi
}

# Get disk size in bytes
get_disk_size() {
    local disk=$1
    diskutil info "$disk" | grep "Disk Size" | awk '{print $5}' | tr -d '()'
}

# Get disk size in GB
get_disk_size_gb() {
    local disk=$1
    local bytes=$(get_disk_size "$disk")
    echo "scale=2; $bytes / 1073741824" | bc
}

# List available disks
list_disks() {
    print_header "Available Disks"
    
    diskutil list | grep -E "^/dev/disk[0-9]+" | while read -r line; do
        local disk=$(echo "$line" | awk '{print $1}' | sed 's/.*disk/disk/')
        local info=$(diskutil info "$disk" 2>/dev/null)
        
        if echo "$info" | grep -q "Protocol.*USB\|Protocol.*SATA\|Solid State"; then
            local size=$(echo "$info" | grep "Disk Size" | awk '{print $3, $4}')
            local name=$(echo "$info" | grep "Device / Media Name" | cut -d: -f2- | xargs)
            local protocol=$(echo "$info" | grep "Protocol" | cut -d: -f2- | xargs)
            
            print_message "$CYAN" "📀 /dev/$disk"
            echo "   Name: $name"
            echo "   Size: $size"
            echo "   Protocol: $protocol"
            echo ""
        fi
    done
}

#reset mountable format
reset_disk_hfs_gpt() {
    local disk="$1"

    print_message "$YELLOW" "No mount point detected. Resetting $disk to HFS+ (GPT)..."

    diskutil unmountDisk "$disk" >/dev/null 2>&1 || true
    sleep 2

    diskutil eraseDisk JHFS+ BENCH GPT "$disk" 2>&1 | tee -a "$RESULTS_LOG"

    # wait for mount
    local timeout=15
    while (( timeout > 0 )); do
        local mp
        mp="$(mountcheck "$disk" || true)"
       if [[ -n "$mp" && -d "$mp" ]]; then
            print_message "$GREEN" "✓ Disk recovered at $mp"
            echo "$mp"
            return 0
        fi
        sleep 1
        ((timeout--))
    done

    print_message "$RED" "Failed to recover disk $disk"
    return 1
}


# Fill disk to capacity
fill_disk() {
    local disk=$1
    local mount_point=$2
    
    print_header "Filling Disk: $disk"
    
    if [ ! -d "$mount_point" ]; then
        print_message "$RED" "ERROR: Mount point not accessible: $mount_point"
        return 1
    fi
    
    # Get available space
    local available_kb=$(df -k "$mount_point" | tail -1 | awk '{print $4}')
    local available_bytes=$((available_kb * 1024))
    local available_gb=$(echo "scale=2; $available_bytes / 1073741824" | bc)
    
    print_message "$BLUE" "Available space: ${available_gb} GB"
    
    # leave 2GB free instead of 5%
    local reserve_bytes=$((2 * 1024 * 1024 * 1024))
    local target_bytes=$((available_bytes - reserve_bytes))
    local target_gb=$(echo "scale=2; $target_bytes / 1073741824" | bc)
    
    print_message "$YELLOW" "Filling ${target_gb} GB (2GB left for speed test)..."
    
    local fill_dir="${mount_point}/FILL"
    mkdir -p "$fill_dir"
    
    local start_time=$(python3 -c 'import time; print(time.time())')
    
    # Calculate number of 1GB files
    local gb_files=$((target_bytes / 1073741824))
    local remaining_bytes=$((target_bytes % 1073741824))
    local remaining_mb=$((remaining_bytes / 1048576))
    
    print_message "$CYAN" "Creating ${gb_files} x 1GB files + ${remaining_mb}MB"
    
    # Create 1GB files
    for i in $(seq 1 $gb_files); do
        echo -ne "\r${GREEN}Progress: $i/${gb_files} GB files ($(echo "scale=1; $i * 100 / $gb_files" | bc)%)${NC}"
        dd if=/dev/zero of="${fill_dir}/fill_${i}.dat" bs=1m count=1024 2>/dev/null
    done
    echo ""
    
    # Create remainder file
    if [ $remaining_mb -gt 0 ]; then
        dd if=/dev/zero of="${fill_dir}/fill_remainder.dat" bs=1m count=$remaining_mb 2>/dev/null
    fi
    
    local end_time=$(python3 -c 'import time; print(time.time())')
    duration=$(echo "$end_time - $start_time" | bc | xargs printf "%.1f")

    print_message "$GREEN" "✓ Disk filled in ${duration} seconds"
    
    # Verify fill
    local used=$(df -h "$mount_point" | tail -1 | awk '{print $5}')
    print_message "$BLUE" "Disk usage: $used"
    
    return 0
}

# Benchmark format operation
benchmark_format() {
    local disk=$1
    local format_name=$2
    local filesystem=$3
    local partition_scheme=$4
    local test_number=$5
    local total_tests=$6
    local fill_before=$7
    local extra_args=""
    local TEST_PW="password123"

    print_header "Test $test_number/$total_tests: $format_name" 
    log_message "Starting benchmark: $format_name ($partition_scheme)"
    
    # Unmount disk
    diskutil unmountDisk "$disk" 2>/dev/null || true
    sleep 2
    
    # Format and measure time
    print_message "$YELLOW" "Formatting with: $filesystem ($partition_scheme)..."
    print_message "$CYAN" "Fill before format: $([ "$fill_before" = "yes" ] && echo "YES" || echo "NO")"
    

    if [[ "$format_name" =~ [Ee]ncrypted ]]; then
        extra_args="-passphrase $TEST_PW"
        if [[ "$filesystem" == "JHFS+" ]]; then filesystem="JHFS+X"; fi
    fi
    
    local scheme_cmd=""
    case "$partition_scheme" in
       "MBR"|"FDisk") scheme_cmd="MBR" ;;
       "GPT"|"GUID")  scheme_cmd="GPT" ;;
       "APM")         scheme_cmd="APM" ;;
       *)             scheme_cmd="GPT" ;; # Default to GPT
    esac


    print_message "$YELLOW" "Formatting with: $filesystem ($partition_scheme)..."
    local start_time=$(python3 -c 'import time; print(time.time())')

    diskutil eraseDisk "$filesystem" "BENCH" $extra_args "$scheme_cmd" "$disk" 2>&1 | tee -a "$RESULTS_LOG"
    
    local end_time=$(python3 -c 'import time; print(time.time())')
    duration=$(echo "$end_time - $start_time" | bc | xargs printf "%.1f")

    print_message "$GREEN" "✓ Format completed in ${duration} seconds"
    
    # Wait for mount
    
    print_message "$CYAN" "Waiting for volume to mount..."
    local timeout=10
    local mounted=false
    while [ $timeout -gt 0 ]; do
        # Check for mount point anywhere on the parent disk's children
          mount_point="$(mountcheck "$disk" || true)"
        if [ -n "$mount_point" ] && [ -d "$mount_point" ]; then
            mounted=true
            break
        fi
        sleep 1
        ((timeout--))
    done

    if [ "$mounted" = false ]; then
        mount_point="/Volumes/BENCH" # Fallback guess
    fi
    
    log_message "Format completed: $format_name - Mount: $mount_point - Duration: ${duration}s"
    
    # Store result
    RESULTS+=("$test_number,$format_name,$filesystem,$partition_scheme,$fill_before,$duration,$mount_point")
    
    echo "$duration"
}

#speed test

Speedtest() {
    local mount_point="$1"
    local phase="$2"
    local test_file="$mount_point/test.bin"
    local size_mb=1024
    local free_mb

    local write_out write_bytes write_secs write_mbps
    local read_out  read_bytes read_secs read_mbps

    [ -d "$mount_point" ] || { echo "N/A,N/A"; return 0; }

    free_mb=$(df -m "$mount_point" | tail -1 | awk '{print $4}')
    if (( free_mb < size_mb )); then
        echo "DISK_FULL,DISK_FULL"
        return 0
    fi
    export LC_ALL=C

    sync
    write_out=$(dd if=/dev/zero of="$test_file" bs=1m count="$size_mb" conv=sync 2>&1 || true)
    sync
    write_bytes=$(echo "$write_out" | awk '/bytes transferred/ {print $1}')
    write_secs=$(echo "$write_out"  | sed -n 's/.* in \([0-9.]*\) secs.*/\1/p')
    if [[ -z "$write_bytes" || -z "$write_secs" || "$write_secs" == "0" ]]; then
        write_mbps="N/A"
    else
        write_mbps=$(echo "scale=2; ($write_bytes / 1048576) / $write_secs" | bc)
    fi
    sleep 2
    read_out=$(dd if="$test_file" of=/dev/null bs=1m 2>&1 || true)
    read_bytes=$(echo "$read_out" | awk '/bytes transferred/ {print $1}')
    read_secs=$(echo "$read_out"  | sed -n 's/.* in \([0-9.]*\) secs.*/\1/p')
    if [[ -z "$read_bytes" || -z "$read_secs" || "$read_secs" == "0" ]]; then
        read_mbps="N/A"
    else
        read_mbps=$(echo "scale=2; ($read_bytes / 1048576) / $read_secs" | bc)
    fi

    rm -f "$test_file"

    echo "${read_mbps},${write_mbps}"
}

#mount check
mountcheck() {
  local disk="$1"
  local found_mount=""
  local mp=""

  for i in 1 2; do
    local slice="${disk}s$i"

    found_mount=$(diskutil info -plist "$slice" 2>/dev/null | \
                  plutil -extract MountPoint raw - 2>/dev/null)

    if [[ -n "$found_mount" && -d "$found_mount" ]]; then
      mp="${found_mount% [0-9]*}"
      echo "$mp"
      return 0
    fi
  done

  return 1
}

# Main benchmark execution
run_benchmark() {
    local disk=$1
    local fill_before_format=$2
    duration="0.0"
    readspeed_before=""
    writespeed_before=""
    readspeed_after=""
    writespeed_after=""
    local mount_point
    local fill_status="no"
    
    print_header "SSD Format Benchmark - Starting"
    
    print_message "$BLUE" "Target Disk: $disk"
    print_message "$BLUE" "Fill before format: $fill_before_format"
    print_message "$BLUE" "Results will be saved to: $RESULTS_CSV"
    
    local disk_size_gb=$(get_disk_size_gb "$disk")
    print_message "$CYAN" "Disk size: ${disk_size_gb} GB"
    
    echo ""
    read -p "$(echo -e ${RED}WARNING: All data on $disk will be erased. Continue? [y/N]: ${NC})" -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "$RED" "Benchmark cancelled."
       Return 1
    fi
    
    # Define test matrix
    # Format: "Display Name|Filesystem|Partition Scheme"
    declare -a TEST_MATRIX=(
    # --- HFS+ (Mac OS Extended) Variants ---
    "HFS+ Journaled (MBR)|JHFS+|MBR"
    "HFS+ Journaled (GPT)|JHFS+|GPT"
    "HFS+ Journaled (APM)|JHFS+|APM"
    "HFS+ Case-sensitive Journaled (GPT)|JHFS+X|GPT"
    "HFS+ Case-sensitive Journaled (MBR)|JHFS+X|MBR"
    "HFS+ Case-sensitive Journaled (APM)|JHFS+X|APM"
    
    # --- APFS Variants (Note: APFS officially requires GPT) ---
    "APFS (GPT)|APFS|GPT"
    "APFS Case-sensitive (GPT)|APFSI|GPT"
    "APFS Encrypted (GPT)|APFS|GPT" # Encrypted APFS is usually handled via 'diskutil apfs' post-format
    "APFS Case-sensitive Encrypted (GPT)|APFSI|GPT"

    # --- FAT32 (MS-DOS) Variants ---
    "MS-DOS FAT32 (MBR)|FAT32|MBR"
    "MS-DOS FAT32 (GPT)|FAT32|GPT"
    "MS-DOS FAT32 (APM)|FAT32|APM"

    # --- ExFAT Variants ---
    "ExFAT (MBR)|ExFAT|MBR"
    "ExFAT (GPT)|ExFAT|GPT"
    "ExFAT (APM)|ExFAT|APM"
    
    )
    
    local total_tests=${#TEST_MATRIX[@]}
    local current_test=0

      # Initialize disk
      reset_disk_hfs_gpt "$disk"|| true

    # Initialize CSV
    echo "Test_Number,Format_Name,Filesystem,Partition_Scheme,Filled_Before,Duration_Seconds,ReadSpeed_before,WriteSpeed_before,Readspeed_after,Writespeed_after,Timestamp" > "$RESULTS_CSV"

    # Run tests
    for test_config in "${TEST_MATRIX[@]}"; do
        current_test=$((current_test + 1))
        
        IFS='|' read -r display_name filesystem partition_scheme <<< "$test_config"

        mount_point="$(mountcheck "$disk" || true)"
        echo "mount point: $mount_point"

        fill_status="no"
         if [ "$fill_before_format" = "yes" ] && [ $current_test -gt 1 ]; then
          fill_status="yes"
            if [ -n "$mount_point" ] && [ -d "$mount_point" ]; then
             echo "fill disk start"
               sleep 5
               fill_disk "$disk" "$mount_point"
              echo "fill disk complete $read"
            else
                print_message "$YELLOW" "Warning: Could not fill disk, mount point not found"
                fill_status="NG"
            fi
        fi

        # Run speedtest before
          echo "speed test before format start"
          IFS=',' read readspeed_before writespeed_before < <(Speedtest "$mount_point" before)
          echo "speed test before format read speed: ${readspeed_before}, write speed: ${writespeed_before}"

        # Run benchmark
        benchmark_format "$disk" "$display_name" "$filesystem" "$partition_scheme" "$current_test" "$total_tests" "$fill_status"
      
        # Run speedtest
         echo "speed test after format start"
         IFS=',' read readspeed_after writespeed_after < <(Speedtest "$mount_point" after)
         echo "speed test after format read speed: ${readspeed_after}, write speed: ${writespeed_after}"

        # Add to CSV
        echo "$current_test,\"$display_name\",$filesystem,$partition_scheme,$fill_status,$duration,$readspeed_before,$writespeed_before,$readspeed_after,$writespeed_after,$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULTS_CSV"


        mount_point="$(mountcheck "$disk" || true)"
        if [[ -z "$mount_point" ]]; then
          reset_disk_hfs_gpt "$disk"|| true
        fi
        
        # Pause between tests
        sleep 3
    done
    
    print_header "Benchmark Complete!"
    
    # Generate summary
    print_message "$GREEN" "✓ All tests completed successfully"
    print_message "$CYAN" "Results saved to: $RESULTS_CSV"
    print_message "$CYAN" "Log file: $RESULTS_LOG"
    
    echo ""
    print_message "$BLUE" "Summary of Results:"
    echo ""
    
    # Display results table
    printf "%-5s %-45s %-8s %-10s\n" "Test" "Format" "Filled?" "Time (s)"
    printf "%.s-" {1..80}
    echo ""
    
    tail -n +2 "$RESULTS_CSV" | while IFS=',' read -r test_num format fs scheme filled duration mount time; do
        format_clean=$(echo "$format" | tr -d '"')
        printf "%-5s %-45s %-8s %-10s\n" "$test_num" "$format_clean" "$filled" "$duration"
    done
    
    echo ""
}

# Quick benchmark (empty disk only)
quick_benchmark() {
    local disk=$1
    
    print_header "Quick Benchmark (Empty Disk Only)"
    run_benchmark "$disk" "no"
}

# Full benchmark (with filled disk)
full_benchmark() {
    local disk=$1
    
    print_header "Full Benchmark (With Filled Disk)"
    run_benchmark "$disk" "yes"
}

# Analyze results
analyze_results() {
    if [ ! -f "$RESULTS_CSV" ]; then
        print_message "$RED" "No results file found. Run a benchmark first."
        return
    fi
    
    print_header "Benchmark Analysis"
    
    # Find latest results file if no specific file provided
    local latest_csv=$(ls -t ${LOG_DIR}/benchmark_results_*.csv 2>/dev/null | head -1)
    
    if [ -z "$latest_csv" ]; then
        print_message "$RED" "No results files found in $LOG_DIR"
        return
    fi
    
    print_message "$CYAN" "Analyzing: $latest_csv"
    echo ""
    
    # Extract and analyze data
    print_message "$YELLOW" "Format Time Comparison:"
    echo ""
    
    # Group by filled status
    print_message "$BLUE" "Empty Disk Formats:"
    awk -F',' 'NR>1 && $5=="no" {printf "  %-45s %8.2f seconds\n", $2, $6}' "$latest_csv" | tr -d '"'
    
    echo ""
    print_message "$BLUE" "Filled Disk Formats:"
    awk -F',' 'NR>1 && $5=="yes" {printf "  %-45s %8.2f seconds\n", $2, $6}' "$latest_csv" | tr -d '"'
    
    echo ""
    print_message "$GREEN" "Fastest Format (Empty):"
    awk -F',' 'NR>1 && $5=="no" {print $2,$6}' "$latest_csv" | sort -t' ' -k2 -n | head -1 | awk '{printf "  %s - %.2f seconds\n", substr($0, 1, length($0)-length($NF)-1), $NF}' | tr -d '"'
    
    echo ""
    print_message "$GREEN" "Fastest Format (Filled):"
    awk -F',' 'NR>1 && $5=="yes" {print $2,$6}' "$latest_csv" | sort -t' ' -k2 -n | head -1 | awk '{printf "  %s - %.2f seconds\n", substr($0, 1, length($0)-length($NF)-1), $NF}' | tr -d '"'
    
    echo ""
    print_message "$YELLOW" "Slowest Format (Empty):"
    awk -F',' 'NR>1 && $5=="no" {print $2,$6}' "$latest_csv" | sort -t' ' -k2 -rn | head -1 | awk '{printf "  %s - %.2f seconds\n", substr($0, 1, length($0)-length($NF)-1), $NF}' | tr -d '"'
    
    echo ""
    print_message "$YELLOW" "Slowest Format (Filled):"
    awk -F',' 'NR>1 && $5=="yes" {print $2,$6}' "$latest_csv" | sort -t' ' -k2 -rn | head -1 | awk '{printf "  %s - %.2f seconds\n", substr($0, 1, length($0)-length($NF)-1), $NF}' | tr -d '"'
    
    echo ""
}

# Main menu
main_menu() {
    while true; do
        clear
        print_header "macOS SSD Format Benchmark Tool v${SCRIPT_VERSION}"
        
        echo "1. List available disks"
        echo "2. Quick benchmark (empty disk only)"
        echo "3. Full benchmark (with filled disk)"
        echo "4. 2 + 3"
        echo "5. Analyze latest results"
        echo "6. View results directory"
        echo "7. Exit"
        echo ""
        
        read -p "$(echo -e ${CYAN}Select option [1-6]: ${NC})" choice
        echo ""
        
        case $choice in
            1)
                list_disks
                read -p "Press Enter to continue..."
                ;;
            2)
                list_disks
                read -p "Enter disk number (e.g., 2 for /dev/disk2): " disk_num
                local disk=$(get_disk_identifier "$disk_num")
                
                if [ -z "$disk" ]; then
                    print_message "$RED" "Invalid disk identifier"
                else
                    quick_benchmark "$disk"
                fi
                read -p "Press Enter to continue..."
                ;;
            3)
                list_disks
                read -p "Enter disk number (e.g., 2 for /dev/disk2): " disk_num
                local disk=$(get_disk_identifier "$disk_num")
                
                if [ -z "$disk" ]; then
                    print_message "$RED" "Invalid disk identifier"
                else
                    full_benchmark "$disk"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                list_disks
                read -p "Enter disk number (e.g., 2 for /dev/disk2): " disk_num
                local disk=$(get_disk_identifier "$disk_num")
                
                if [ -z "$disk" ]; then
                    print_message "$RED" "Invalid disk identifier"
                else
                    quick_benchmark "$disk"
                    full_benchmark "$disk"
                fi
                read -p "Press Enter to continue..."
                ;;
            5)
                analyze_results
                read -p "Press Enter to continue..."
                ;;
            6)
               print_message "$CYAN" "Results directory: $LOG_DIR"
                ls -lh "$LOG_DIR"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            7)
                print_message "$GREEN" "Exiting..."
                exit 0
                ;;
            *)
                print_message "$RED" "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_message "$RED" "ERROR: This script requires macOS"
        return 1
    fi
    
    if ! command -v bc &> /dev/null; then
        print_message "$RED" "ERROR: 'bc' command not found"
        print_message "$YELLOW" "Install with: brew install bc"
        return 1
    fi
    
    if [ "$EUID" -ne 0 ]; then
        print_message "$YELLOW" "Warning: This script should be run as root for disk operations"
        print_message "$YELLOW" "Some operations may fail without sudo privileges"
        echo ""
    fi
}

# Script entry point
print_header "macOS SSD Format Benchmark Tool"
check_prerequisites
main_menu
