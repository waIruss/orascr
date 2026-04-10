#!/bin/bash

CUTOFF_DATE=$(date -d "6 months ago" +%Y-%m-%d)

echo "Scanning for failovers on or after: $CUTOFF_DATE"
echo "Filtering: 3-min deduplication & databases with >1 occurrence..."
echo "----------------------------------------------------"

# Combine both log types into a single stream
(
  find /app/oracle -type f -path "*/observer*/*.log" -exec cat {} + 2>/dev/null
  find /app/oracle -type f -path "*/observer*/log_archive/*.gz" -exec zcat {} + 2>/dev/null
) | \
awk -v cutoff="$CUTOFF_DATE" '
# STAGE 1: FLATTEN MULTILINE LOGS
/^[0-9]{4}-[0-9]{2}-[0-9]{2}T/ {
    date_str = substr($0, 1, 19)
}
/Initiating Fast-Start Failover to database/ {
    split($0, arr, "\"")
    raw_db = arr[2]
    db_name = substr(raw_db, 1, length(raw_db) - 1)
}
/Performing failover NOW, please wait.../ {
    if (date_str != "" && db_name != "" && date_str >= cutoff) {
        printf "%s; %s; \"Performing failover NOW, please wait...\"\n", date_str, db_name
        date_str = ""
        db_name = ""
    }
}' | \
sort | \
awk '
# STAGE 2 & 3: DEDUPLICATE (3-MIN) AND COUNT
{
    # Extract the timestamp and DB name from the newly flattened line
    split($0, parts, "; ")
    date_str = parts[1]
    db_name = parts[2]

    # Convert the ISO timestamp into Epoch seconds so we can do math on it
    # We replace dashes and the "T" with spaces to feed it into mktime()
    time_spec = date_str
    gsub(/[-T:]/, " ", time_spec)
    epoch = mktime(time_spec)

    # Check if this DB was seen less than 180 seconds (3 mins) ago
    if (epoch - last_seen[db_name] >= 180) {
        
        # Update the last_seen time for this specific DB
        last_seen[db_name] = epoch
        
        # Save the valid event into memory
        event_count++
        event_lines[event_count] = $0
        
        # Tally the valid occurrences
        db_occurrences[db_name]++
    }
}
END {
    # Print only events belonging to a DB that failed over more than once
    for (i = 1; i <= event_count; i++) {
        split(event_lines[i], parts, "; ")
        check_db = parts[2]
        
        if (db_occurrences[check_db] > 1) {
            print event_lines[i]
        }
    }
}'

echo "----------------------------------------------------"
echo "Scan complete."
