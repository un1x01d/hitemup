#!/bin/bash

# Define the input file containing the list of links
links_file="links"
output_file="temp/proxies.raw"

# Ensure the output file is empty or create it if it doesn't exist
> "$output_file"

# Download each link and consolidate the results
echo "# Downloading all the source files"
while IFS= read -r link; do
  curl -sO "$link"
done < "$links_file"

# Combine the downloaded files, remove duplicates, and write to the output file
echo "# Merging downloaded files"
cat *.txt | sort -u > "$output_file"

# Clean up temporary files
echo "# Cleaning Up"
rm -f *.txt *.txt.*

[ -e temp/proxies.raw ] && echo "Saved to $output_file"
