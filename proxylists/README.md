# Link Downloader Script

This script downloads content from a list of links, consolidates the results, removes duplicates, and saves the output to a specified file.

## Usage

1. Ensure you have a file named `links` in the same directory containing the list of links to download.
2. Run the script:

    ```sh
    ./sync-raw-file.sh
    ```

## Script Details

- **Input File**: `links` (a file containing the list of links to download)
- **Output File**: `temp/proxies.raw`

## Description

- Downloads each link listed in the `links` file using `curl`.
- Consolidates the downloaded content into `temp/proxies.raw`, ensuring no duplicates.
- Cleans up temporary files after processing.

# VeriProxy Script

This script verifies a list of proxies using multiple workers, categorizes them by country, and consolidates the results.

## Usage

```sh
./VeriProxy.sh <input_file> [number_of_workers]
```

`./VeriProxy.sh proxies.txt 5`
This runs the script with 5 workers to verify proxies listed in proxies.txt.

## Description
Splits the input file into chunks based on the number of workers.
Checks each proxy by making a request to ipinfo.io to determine its country.
Valid proxies are saved in the verified directory, categorized by country.
A consolidated list of verified proxies is saved in proxies.verified.

## Features
Concurrency: Uses multiple workers for parallel processing.
Proxy Validation: Verifies proxies and categorizes them by country.
Output: Consolidates results and removes duplicates.
Dependencies
Ensure the following dependencies are installed:

## Dependencies
`curl`
`awk`
`flock (Linux)`
`shlock (macOS)`
