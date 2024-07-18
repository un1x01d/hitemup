#!/bin/bash

# Function to display usage information
usage() {
  echo "Usage: $0 <input_file> [number_of_workers]"
  exit 1
}

# Check if an input file and number of workers are provided
if [ -z "$1" ]; then
  usage
fi

input_file="$1"
num_workers="${2:-1}"  # Default to 1 worker if not provided

verified_dir="verified-by-country"
verified_file="proxies.verified"
tmp_dir=".tmp_files"

# Create necessary directories
mkdir -p "$tmp_dir"
mkdir -p "$verified_dir"

# Trap to ensure cleanup on exit
cleanup() {
  echo "Cleaning up..."
  rm -rf "$tmp_dir"
  rm -rf "*.lock"
  rm -f /tmp/proxy_test_output
  for pid in "${worker_pids[@]}"; do
    kill "$pid" 2>/dev/null
  done
  echo "All worker processes terminated."
  exit 1
}
trap cleanup SIGINT

# Define a list of common proxy ports (excluding port 80)
declare -a common_ports=("8080" "3128" "1080" "8888" "81" "8000" "8880")
common_ports_regex=$(IFS=\|; echo "${common_ports[*]}")

# Load proxies into memory from the input file, filtering by common ports
mapfile -t proxies < <(grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:(${common_ports_regex})$" "$input_file" | sort -u)

# Function to test if a proxy is working and get its country
test_proxy() {
  local proxy=$1
  local worker_id=$2
  # Use curl to test the proxy and get the country with a 100ms timeout
  response=$(curl -x "$proxy" -s -w "%{http_code}" --max-time 1 ipinfo.io/country -o /tmp/proxy_test_output)
  http_code=$(tail -n1 <<< "$response")

  if [[ "$http_code" == "200" ]]; then
    content=$(cat /tmp/proxy_test_output)
    if ! grep -qi "<html>" <<< "$content"; then
      country=$(echo "$content" | tr -d '[:space:]')  # Remove any surrounding whitespace
      # Ensure country code is valid (two uppercase letters)
      if [[ "$country" =~ ^[A-Z]{2}$ ]]; then
        # Create directory for the country if it doesn't exist
        mkdir -p "$verified_dir/$country"
        # Add the valid proxy to the country-specific file
        echo "$proxy" >> "$verified_dir/$country/proxies.txt"
        # Append the valid proxy to the general verified file in a thread-safe manner
        (flock -x 200; echo "$proxy" >> "$verified_file") 200>"$verified_file.lock"
        # Output the valid proxy in green with the worker number
        echo -e "\e[32m- \e[1m[\e[34m$worker_id\e[0;32m]: $proxy\e[0m"
      fi
    fi
  fi
}

# Function to process proxies in parallel
process_proxies() {
  local worker_id=$1
  local start_index=$2
  local end_index=$3

  # Record start time for the worker
  start_time=$(date +%s%N)
  echo -e "- \e[1m[\e[34m$worker_id\e[0m\e[1m] started at $(date +"%T")\e[0m"

  # Process proxies in the given range
  for ((i = start_index; i < end_index; i++)); do
    proxy="${proxies[$i]}"
    test_proxy "$proxy" "$worker_id"
  done

  # Record end time for the worker and calculate duration
  end_time=$(date +%s%N)
  duration=$(echo "scale=2;($end_time - $start_time) / 1000000000" | bc)
  echo -e "- \e[1m[\e[34m$worker_id\e[0m\e[1m] finished at $(date +"%T"), duration: ${duration}s\e[0m"
}

# Function to periodically count lines in the verified file every 5 minutes
count_verified_lines() {
  while true; do
    if [ -f "$verified_file" ]; then
      line_count=$(wc -l < "$verified_file")
    else
      line_count=0
    fi
    echo "Verified proxies: $line_count"
    sleep 300  # 5 minutes
  done
}

# Start the line counting function in the background
count_verified_lines &
count_pid=$!

# Start timer
overall_start_time=$(date +%s%N)

# Print header with the title in "poison" font, ensuring it fits on one line
title=$(figlet -f poison -w 80 "VeriProxy")
title_length=$(echo "$title" | wc -L)
divider=$(printf "%${title_length}s" | tr ' ' '=')
echo -e "\e[31m$divider\e[0m"
echo -e "\e[32m$title\e[0m"
echo -e "\e[31m$divider\e[0m"
echo "Proxies will be added as they are found and also saved in $verified_file"

# Calculate the number of proxies per worker
total_proxies=${#proxies[@]}
proxies_per_worker=$((total_proxies / num_workers))

# Initialize array to store worker PIDs
worker_pids=()

# Run the verification script on each chunk of proxies in parallel
for ((worker_id = 1; worker_id <= num_workers; worker_id++)); do
  start_index=$(( (worker_id - 1) * proxies_per_worker ))
  end_index=$(( worker_id * proxies_per_worker ))
  if [ $worker_id -eq $num_workers ]; then
    end_index=$total_proxies
  fi
  process_proxies "$worker_id" "$start_index" "$end_index" &
  worker_pids+=($!)
done

# Wait for all background processes to complete
for pid in "${worker_pids[@]}"; do
  wait $pid
done

# Calculate and print the total runtime
overall_end_time=$(date +%s%N)
overall_runtime=$(echo "scale=2;($overall_end_time - $overall_start_time) / 1000000000" | bc)
echo -e "\e[31m$divider\e[0m"
echo "Total runtime: $overall_runtime seconds"

# Kill the background process before exiting
kill $count_pid

# Verify that there are no duplicates post processing
mv $verified_file "$verified_file.tmp"
cat $verified_file.tmp | sort -u > $verified_file
rm -f $verified_file.tmp

# Cleanup all temporary files
cleanup

