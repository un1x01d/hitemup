#!/bin/bash

# Function to display usage information
usage() {
  echo "Usage: $0"
  echo "  -x, --threads [threads]   Number of threads (workers)"
  echo "  -t, --timeout [timeout]   Timeout in seconds for each worker"
  echo "  -u, --url [url]           URL to test against"
  echo "  -g, --get                 Use GET method"
  echo "  -p, --post                Use POST method"
  echo "  -f, --follow              Follow HTTP 301/302 redirects"
}

# Function to check and install dependencies
check_dependencies() {
  local missing_deps=()

  # Check if curl is installed
  if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
  fi

  # Check if awk is installed
  if ! command -v awk &> /dev/null; then
    missing_deps+=("awk")
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # Check if shlock is installed (part of inetutils)
    if ! command -v shlock &> /dev/null; then
      missing_deps+=("shlock (part of inetutils)")
    fi
  else
    # Check if flock is installed
    if ! command -v flock &> /dev/null; then
      missing_deps+=("flock")
    fi
  fi

  if [ ${#missing_deps[@]} -ne 0 ]; then
    echo "The following dependencies are missing: ${missing_deps[*]}"
    echo "Do you want to install them? (y/n)"
    read -r install_deps

    if [ "$install_deps" == "y" ]; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if ! command -v brew &> /dev/null; then
          echo "Homebrew is required to install dependencies. Please install Homebrew first."
          exit 1
        fi
        for dep in "${missing_deps[@]}"; do
          case $dep in
            "curl") brew install curl ;;
            "awk") echo "awk is typically pre-installed on macOS." ;;
            "shlock (part of inetutils)") brew install inetutils ;;
          esac
        done
      elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command -v apt-get &> /dev/null; then
          sudo apt-get update
          for dep in "${missing_deps[@]}"; do
            case $dep in
              "curl") sudo apt-get install -y curl ;;
              "awk") sudo apt-get install -y gawk ;;
              "flock") sudo apt-get install -y flock ;;
            esac
          done
        elif command -v apk &> /dev/null; then
          # Alpine Linux
          sudo apk update
          for dep in "${missing_deps[@]}"; do
            case $dep in
              "curl") sudo apk add curl ;;
              "awk") sudo apk add gawk ;;
              "flock") sudo apk add util-linux ;;
            esac
          done
        else
          echo "Unsupported package manager. Please install the dependencies manually."
          exit 1
        fi
      else
        echo "Unsupported operating system. Please install the dependencies manually."
        exit 1
      fi
    else
      echo "Please install the missing dependencies and run the script again."
      exit 1
    fi
  fi
}

# Check dependencies before proceeding
check_dependencies

# Initialize variables with default values
url="http://192.168.102.105"
get_method=false
post_method=false
follow_redirects=false
agents_list="agents.txt"
workers=""
timeout=""
generic_ip="203.0.113.1" # Example generic IP address
declare -a worker_pids
declare -a worker_requests
declare -a worker_response_codes

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -x|--threads)
       if ! [[ "$2" =~ ^[0-9]+$ ]]; then
         echo "Error: --threads requires a positive integer argument."
         exit 1
       fi
       workers="$2"
       shift 2
      ;;
    -t|--timeout)
       if ! [[ "$2" =~ ^[0-9]+$ ]]; then
         echo "Error: --timeout requires a positive integer argument."
         exit 1
       fi
       timeout="$2"
       shift 2
      ;;
    -u|--url)
       url="$2"
       shift 2
      ;;
    -g|--get)
       get_method=true
       shift
      ;;
    -p|--post)
       post_method=true
       shift
      ;;
    -f|--follow)
       follow_redirects=true
       shift
      ;;
    *)
       usage ; exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$url" ] || [ -z "$timeout" ] || [ -z "$workers" ]; then
   echo "Missing parameters" >&2 ; exit 1
fi

# Validate method selection
if ! $get_method && ! $post_method; then
   echo "Specify either -g (GET) or -p (POST) method" >&2 ; exit 1
fi

# Colors
RED=$(tput setaf 1)
ORANGE=$(tput setaf 3)
YELLOW=$(tput setaf 11)
GREEN=$(tput setaf 2)
BLUE=$(tput setaf 4)
RESET=$(tput sgr0)

# Display header with centered title
divider="====================================================="
width=$(echo "$divider" | wc -c)

echo -e "${RED}$divider${RESET}"

# Display information
echo -e "${YELLOW}[+] Loading user agents list into memory...${RESET}"
mapfile -t agents_array < "$agents_list"
num_agents=${#agents_array[@]}

if [[ $num_agents -eq 0 ]]; then
  echo "Error: No user agents found in $agents_list"
  exit 1
fi

echo -e "${YELLOW}[+] User agents list loaded into memory.${RESET}"
echo -e "${RED}$divider${RESET}"

# Function to generate a random public IP address
generate_random_ip() {
    while :; do
        octet1=$((RANDOM % 256))
        octet2=$((RANDOM % 256))
        octet3=$((RANDOM % 256))
        octet4=$((RANDOM % 256))

        ip="$octet1.$octet2.$octet3.$octet4"

        # Exclude private IP ranges
        if ! [[ $ip =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]]; then
            echo "$ip"
            return
        fi
    done
}

# Function to determine the most common HTTP response code
most_common_code() {
    local codes=("$@")
    local max_count=0
    local max_code=""
    declare -A code_counts

    for code in "${codes[@]}"; do
        ((code_counts[$code]++))
        if (( code_counts[$code] > max_count )); then
            max_count=${code_counts[$code]}
            max_code=$code
        fi
    done
    echo $max_code
}

# Function to run curl requests
run_curl() {
    local worker_id=$1
    local start_time
    start_time=$(date +%s)
    local request_count=0
    local response_codes=()

    while true; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ "$elapsed_time" -ge "$timeout" ]; then
            most_common=$(most_common_code "${response_codes[@]}")
            echo "[!] Worker $worker_id timed out ($timeout seconds) after sending $request_count requests. Most common HTTP response code: $most_common."
            worker_requests[$worker_id]=$request_count
            worker_response_codes[$worker_id]=$most_common
            break
        fi

        # Randomly select a user agent from the list
        user_agent="${agents_array[RANDOM % num_agents]}"

        # Generate a random public IP address
        random_ip=$(generate_random_ip)

        # Combine user agent with random IP
        full_user_agent="$user_agent [$random_ip]"

        # Determine the curl method
        if $get_method; then
            method="GET"
        elif $post_method; then
            method="POST"
        fi

        # Determine if we should follow redirects
        if $follow_redirects; then
            follow_flag="--location"
        else
            follow_flag=""
        fi

        # Perform the request and capture the HTTP response code
        response_code=$(curl --silent --output /dev/null --write-out "%{http_code}" --user-agent "$full_user_agent" -H "X-Forwarded-For: $random_ip" -H "X-Generic-IP: $generic_ip" -X "$method" $follow_flag "$url")

        # Increment the count for the received response code
        ((request_count++))
        response_codes+=("$response_code")
    done
}

# Function to get public and private IP addresses
get_ip_addresses() {
    # Get public IP address (IPv4)
    public_ip=$(curl -s 'https://api.ipify.org?format=text')

    # Get private IP address (Linux and macOS compatible)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        private_ip=$(ifconfig en0 | awk '/inet /{print $2}')
    else
        private_ip=$(hostname -I | awk '{print $1}')
    fi

    echo -e "${BLUE}Public:${RESET} $public_ip"
    echo -e "${BLUE}Private:${RESET} $private_ip"
}

# Function to clean up worker processes and report statistics
cleanup() {
    echo -e "${RED}[+] Cleaning up worker processes...${RESET}"
    for pid in "${worker_pids[@]}"; do
        kill "$pid" 2>/dev/null
    done
    echo -e "${RED}[+] All worker processes terminated.${RESET}"

    # Aggregate and display total requests sent
    total_requests=0
    for worker_id in "${!worker_requests[@]}"; do
        total_requests=$((total_requests + worker_requests[$worker_id]))
        echo "[!] Worker $worker_id sent ${worker_requests[$worker_id]} requests. Most common HTTP response code: ${worker_response_codes[$worker_id]}"
    done

    echo -e "${BLUE}[+] Total requests sent: ${total_requests}${RESET}"

    exit
}

# Trap SIGINT (Ctrl+C) signal
trap cleanup SIGINT

# Display additional information
echo -e "${BLUE}Requested Workers:${RESET} $workers"
echo -e "${BLUE}Requested Timeout:${RESET} $timeout seconds"
echo -e "${BLUE}Follow Redirects:${RESET} $follow_redirects"
echo -e "${RED}$divider${RESET}"

# Display IP addresses
get_ip_addresses

# Display target URL
echo -e "${BLUE}Target URL:${RESET} $url"

# Divider after Target URL
echo -e "${RED}$divider${RESET}"

# Start workers in background and store their PIDs
echo -e "${RED}[+] Starting load test with $workers workers, each with a timeout of $timeout seconds.${RESET}"
for ((worker_id = 0; worker_id < workers; worker_id++)); do
    run_curl "$worker_id" &
    worker_pids+=("$!")  # Store PID of each worker
    echo "[+] Started worker $worker_id with PID (${worker_pids[-1]})"
done

# Wait for all workers to finish
echo "[+] Waiting for all workers to complete..."
wait "${worker_pids[@]}"

# Aggregate and display total requests sent
cleanup
