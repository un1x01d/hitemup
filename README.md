# HitEmUp 

## Overview

This script is a tool for testing proxies against a specified URL. It supports sending HTTP GET or POST requests, following HTTP redirects, and utilizes multiple threads (workers) to perform the testing. The script also includes functionality to check for and install necessary dependencies, generate random IP addresses, and report on the performance of proxies.

## Features

- **HTTP Methods:** Supports GET and POST requests.
- **Redirect Handling:** Optionally follows HTTP 301/302 redirects.
- **Multi-Threading:** Configurable number of threads (workers).
- **Customizable:** Set request timeout and specify target URL.
- **Proxy Testing:** Collects proxies that are either alive or slow.
- **Dependency Management:** Checks for missing dependencies and offers to install them.
- **IP Address Reporting:** Displays both public and private IP addresses.
- **Statistics Reporting:** Reports on the number of requests sent and saves successful and slow proxies.

## Requirements

- `curl`
- `awk`
- `figlet`
- `shlock` (macOS) or `flock` (Linux)

## Installation

To ensure that you have the required dependencies, run the script and it will check for missing dependencies. You will be prompted to install them if necessary.

**For macOS:**

Make sure you have [Homebrew](https://brew.sh) installed. The script will use Homebrew to install the necessary dependencies.

**For Linux:**

The script supports both `apt-get` (Debian/Ubuntu) and `apk` (Alpine). Make sure you have the appropriate package manager for your Linux distribution.

## Usage

```bash
./hitemup.sh [options]
