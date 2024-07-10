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

verified_dir="verified/"
verified_file="proxies.verified"
tmp_dir=".tmp_files"

# Create the temporary files directory
mkdir -p "$tmp_dir"

# Trap to ensure cleanup on exit
cleanup() {
  rm -rf "$tmp_dir"
  rm -f /tmp/proxy_test_output
}
trap cleanup EXIT

# Split the input file into the specified number of smaller files
split -n l/"$num_workers" "$input_file" "$tmp_dir/input_file_"

# Ensure all split files are sorted and contain unique entries
for file in "$tmp_dir"/input_file_*; do
  sort -u "$file" -o "$file"
done

# Define a list of common proxy ports (excluding port 80)
declare -a common_ports=("8080" "3128" "1080" "8888" "81" "8000" "8880")
common_ports_regex=$(IFS=\|; echo "${common_ports[*]}")

# Function to test if a proxy is working and get its country
test_proxy() {
  local proxy=$1
  local worker_id=$2
  # Use curl to test the proxy and get the country with a 100ms timeout
  response=$(curl -x "$proxy" -s -w "%{http_code}" --max-time 2 ipinfo.io/country -o /tmp/proxy_test_output)
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

# Function to process each smaller file
process_file() {
  local worker_id=$1
  local file=$2
  local sorted_file="$file.sorted"

  # Record start time for the worker
  start_time=$(date +%s%N)
  echo -e "- \e[1m[\e[34m$worker_id\e[0m\e[1m] started at $(date +"%T")\e[0m"

  # Use grep to filter valid IP:port combinations and sort them
  grep -E "^[1-9][0-9]{0,2}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:(${common_ports_regex})$" "$file" | sort -u > "$sorted_file"

  # Read the sorted file and test each proxy
  while IFS= read -r proxy; do
    test_proxy "$proxy" "$worker_id"
  done < "$sorted_file"

  # Cleanup temporary sorted file
  rm "$sorted_file"
  # Cleanup worker's input file
  rm "$file"

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
title=$(figlet -f poison -w 80 "veriprox")
title_length=$(echo "$title" | wc -L)
divider=$(printf "%${title_length}s" | tr ' ' '=')
echo -e "\e[31m$divider\e[0m"
echo -e "\e[32m$title\e[0m"
echo -e "\e[31m$divider\e[0m"
echo "Proxies will be added as they are found and also saved in $verified_file"

# Display the number of lines in each worker's file
worker_id=1
for file in "$tmp_dir"/input_file_*; do
  line_count=$(wc -l < "$file")
  echo -e "- \e[1m[\e[34m$worker_id\e[0m\e[1m] processing $file: $line_count lines\e[0m"
  worker_id=$((worker_id + 1))
done

# Run the verification script on each smaller file in parallel
worker_id=1
pids=()
for file in "$tmp_dir"/input_file_*; do
  process_file "$worker_id" "$file" &
  pids+=($!)
  worker_id=$((worker_id + 1))
done

# Wait for all background processes to complete
for pid in "${pids[@]}"; do
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
cat $verified_file.tmp | sort -u >> $verified_file
rm -f $verified_file.tmp

# Cleanup all temporary files
cleanup

