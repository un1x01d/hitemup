# Link Downloader Script

This script downloads content from a list of links, consolidates the results, removes duplicates, and saves the output to a specified file.

## Usage

1. Ensure you have a file named `links` in the same directory containing the list of links to download.
2. Run the script:

    ```sh
    ./link_downloader.sh
    ```

## Script Details

- **Input File**: `links` (a file containing the list of links to download)
- **Output File**: `temp/proxies.raw`

## Description

- Downloads each link listed in the `links` file using `curl`.
- Consolidates the downloaded content into `temp/proxies.raw`, ensuring no duplicates.
- Cleans up temporary files after processing.

## Script

```sh
#!/bin/bash

# Define the input file containing the list of links
links_file="links"
output_file="temp/proxies.raw"

# Ensure the output file is empty or create it if it doesn't exist
> "$output_file"

# Download each link and consolidate the results
while IFS= read -r link; do
  curl -sO "$link"
done < "$links_file"

# Combine the downloaded files, remove duplicates, and write to the output file
cat *.txt | sort -u > "$output_file"

[ -e temp/proxies.raw ] && echo "Saved to $output_file"

# Clean up temporary files
rm -f *.txt *.txt.*

