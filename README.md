#!/bin/bash
AWK_SCRIPT='
/^[0-9]{4}-[0-9]{2}-[0-9]{2}T/ {
    date_str = substr($0, 1, 19)
}
/Initiating Fast-Start Failover to database/ {
    split($0, arr, "\"")
    db_name = arr[2]
}
/Performing failover NOW, please wait.../ {
    if (date_str != "" && db_name != "") {
        printf "%s; %s; \"%s\"\n", date_str, db_name, "Performing failover NOW, please wait..."
        date_str = ""
        db_name = ""
    }
}
'

echo "Scanning uncompressed .log files..."
find /home/oracle -type f -path "*/obs*/*.log" \
  -exec awk "$AWK_SCRIPT" {} + 2>/dev/null

echo "Scanning compressed .gz files..."
find /home/oracle -type f -path "*/obs*/log_archive/*.gz" \
  -exec zcat {} + 2>/dev/null | awk "$AWK_SCRIPT"
echo "Scan complete."
