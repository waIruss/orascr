









status_observer() {
  prepare_env "$env"

  echo "ObserverConfigFile=$obsconfig"
  echo "observer configuration file parsing succeeded"

  run_dgmgrl_stdout <<'DGM_IN' 2>&1 | awk '
    BEGIN {
        # Define ANSI Color Codes
        grn = "\033[0;32m"
        ylw = "\033[0;33m"
        red = "\033[0;31m"
        rst = "\033[0m"
    }

    # Capture dbname
    /connect identifier/ {
        split($0, a, "\"")
        target_db = tolower(a[4])
    }

    # Capture FSFO status
    /Fast-Start Failover:/ {
        if (match($0, /Fast-Start Failover:[[:space:]]+([A-Z]+)/, m)) fsfo = m[1]
    }

    # Capture errors
    (/ORA-/ || /Unable to connect/ || /Error:/ || /idle instance/ || /cannot be determined/) {
        error_found = 1
        gsub(/\r/, ""); sub(/^[[:space:]]*/, "", $0);
        if (err_msg == "") err_msg = $0
    }

    # Capture primary
    /^[[:space:]]*Primary:/ {
        if (match($0, /Primary:[[:space:]]+([A-Za-z0-9_]+)/, m)) primary = m[1]
    }

    # Observer part start
    /Observer/ {
        m_flag = ($0 ~ /- Master/) ? "*" : " "
        current_host = ""; p_ping = ""; t_ping = ""
    }
    /Host Name:/ {
        if (match($0, /Host Name:[[:space:]]+([^.[:space:]]+)/, m)) current_host = m_flag m[1]
    }

    # Capture pings + WARN check
    /Last Ping to Primary:/ {
        val = ($0 ~ /unknown/) ? "unknown" : ""
        if (val == "" && match($0, /:[[:space:]]+([0-9]+)/, m)) val = m[1]
        p_ping = val
        if (val == "unknown" || (val != "" && val > 60)) warn_flag = 1
    }
    /Last Ping to Target:/ {
        val = ($0 ~ /unknown/) ? "unknown" : ""
        if (val == "" && match($0, /:[[:space:]]+([0-9]+)/, m)) val = m[1]
        t_ping = val
        if (val == "unknown" || (val != "" && val > 60)) warn_flag = 1

        if (current_host != "") {
            obs_count++
            block = sprintf("%s: %s:%s", current_host, p_ping, t_ping)
            entry = sprintf("%-18s", block)
            hosts = (hosts == "" ? "" : hosts " | ") entry
        }
    }

    # Summary
    END {
        fsfo_val = (fsfo != "") ? fsfo : "N/A"
        db_label = "Primary: " ((primary != "") ? primary : (target_db != "") ? target_db : "unknown")

        if (primary != "") {
            status_tag = (warn_flag == 1 || obs_count < 3) ? ylw "WARN" rst : grn "OK" rst

            if (hosts == "") {
                printf "%-20s | FSFO: %-8s | %-58s | %s\n", db_label, fsfo_val, "No observers found", red "ERROR" rst
            } else {
                # Print everything left-aligned
                printf "%-20s | FSFO: %-8s | %s | %s\n", db_label, fsfo_val, hosts, status_tag
            }
        } else {
            final_err = (err_msg != "" ? err_msg : "Database unavailable")
            if (length(final_err) > 58) final_err = substr(final_err, 1, 55) "..."
            printf "%-20s | FSFO: %-8s | %-58s | %s\n", db_label, "N/A", final_err, red "ERROR" rst
        }
    }
  '
SHOW OBSERVERS
DGM_IN
}
