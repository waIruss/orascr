#!/bin/bash

# Calculate the cutoff date (6 months ago)
CUTOFF_DATE=$(date -d "6 months ago" +%Y-%m-%d)

echo "Scanning for failovers on or after: $CUTOFF_DATE"
echo "Filtering out databases with only 1 occurrence..."
echo "----------------------------------------------------"

# Group both find commands in parentheses to combine their output into one stream.
# We use 'cat' for uncompressed logs and 'zcat' for compressed logs.
(
  find /app/oracle -type f -path "*/observer*/*.log" -exec cat {} + 2>/dev/null
  find /app/oracle -type f -path "*/observer*/log_archive/*.gz" -exec zcat {} + 2>/dev/null
) | awk -v cutoff="$CUTOFF_DATE" '

# 1. Match Date
/^[0-9]{4}-[0-9]{2}-[0-9]{2}T/ {
    date_str = substr($0, 1, 19)
}

# 2. Match Database Name
/Initiating Fast-Start Failover to database/ {
    split($0, arr, "\"")
    raw_db = arr[2]
    
    # Cut off the last character of the DB name (e.g., tstdb1 -> tstdb)
    db_name = substr(raw_db, 1, length(raw_db) - 1)
}

# 3. Match Trigger Line
/Performing failover NOW, please wait.../ {
    if (date_str != "" && db_name != "" && date_str >= cutoff) {
        
        # Save the fully formatted line into memory (indexed by event_count)
        event_count++
        event_lines[event_count] = date_str "; " db_name "; \"Performing failover NOW, please wait...\""
        
        # Tally the occurrences of this specific trimmed DB name
        db_occurrences[db_name]++
        
        # Clear variables for the next block
        date_str = ""
        db_name = ""
    }
}

# 4. After scanning ALL files, process the saved data
END {
    # Loop through all the events we saved in memory
    for (i = 1; i <= event_count; i++) {
        
        # Extract the db_name from the saved string to check its tally
        split(event_lines[i], parts, "; ")
        check_db = parts[2]
        
        # If this DB occurred more than once across all logs, print the line
        if (db_occurrences[check_db] > 1) {
            print event_lines[i]
        }
    }
}
'

echo "----------------------------------------------------"
echo "Scan complete."
