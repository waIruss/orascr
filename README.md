#!/usr/bin/env bash
# RAC PMON + HugePages + Semaphores + MemAvailable + ASM DATA free GB (via asmcmd on local node)
# HugePage = 2 MB; memory values shown in GB (1 decimal)

set -euo pipefail

# Discover nodes
if [[ -z "${NODES:-}" ]]; then
  if ! command -v olsnodes >/dev/null 2>&1; then
    echo "[Error] olsnodes not found and \$NODES not set." >&2
    exit 1
  fi
  mapfile -t nodes < <(olsnodes)
else
  # shellcheck disable=SC2206
  nodes=(${NODES})
fi

local_node=$(hostname -s | tr '[:upper:]' '[:lower:]')
SSH_USER="${SSH_USER:-$(id -un)}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no)

printf "%-15s %-15s %-18s %-17s %-9s %-12s %-10s\n" \
  "Node" "Instance_Count" "HugePages_Free_GB" "Sem_Used/Total" "Used_%" "MemAvail_GB" "ASM_DATA_GB"
printf "%-15s %-15s %-18s %-17s %-9s %-12s %-10s\n" \
  "---------------" "---------------" "------------------" "-----------------" "---------" "------------" "-----------"

for node in "${nodes[@]}"; do
  node_lc=$(echo "$node" | tr '[:upper:]' '[:lower:]')

  # DB instance count (exclude ASM)
  inst_count=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${node}" \
    "ps -ef | grep pmon | grep -vi asm | grep -v grep | wc -l" 2>/dev/null || echo "N/A")

  # HugePages_Free -> GB (2 MB per page)
  hp_free_pages=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${node}" \
    "grep -E '^HugePages_Free:' /proc/meminfo | awk '{print \$2}'" 2>/dev/null || echo "N/A")
  if [[ "$hp_free_pages" =~ ^[0-9]+$ ]]; then
    hp_free_gb=$(awk -v pages="$hp_free_pages" 'BEGIN{printf "%.1f", pages * 2 / 1024}')
  else
    hp_free_gb="N/A"
  fi

  # Semaphore total (SEMMNS)
  sem_total=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${node}" \
    "awk '{print \$2}' /proc/sys/kernel/sem 2>/dev/null" 2>/dev/null || echo "")
  [[ -z "$sem_total" ]] && sem_total="N/A"

  # Semaphore used (sum of nsems)
  sem_used=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${node}" \
    "if [[ -r /proc/sysvipc/sem ]]; then
       awk 'NR==1{for(i=1;i<=NF;i++) if (\$i==\"nsems\") col=i; next} {sum+=(\$col? \$col:0)} END{print (sum==\"\"?0:sum)}' /proc/sysvipc/sem
     else
       echo 0
     fi" 2>/dev/null || echo "N/A")

  if [[ "$sem_used" =~ ^[0-9]+$ ]] && [[ "$sem_total" =~ ^[0-9]+$ ]] && [[ "$sem_total" -gt 0 ]]; then
    sem_pct=$(awk -v u="$sem_used" -v t="$sem_total" 'BEGIN{printf "%.1f", (u/t)*100}')
    sem_pair="${sem_used}/${sem_total}"
  else
    sem_pct="N/A"
    sem_pair="${sem_used}/${sem_total}"
  fi

  # MemAvailable -> GB
  mem_avail_gb=$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${node}" \
    "grep -E '^MemAvailable:' /proc/meminfo | awk '{printf \"%.1f\", \$2/1048576}'" 2>/dev/null || echo "N/A")

  # ASM DATA free (local only)
  if [[ "$node_lc" == "$local_node" ]]; then
    if command -v asmcmd >/dev/null 2>&1; then
      asm_sid=$(ps -ef | grep -E 'pmon_.*\+asm' -i | awk -F_ '/pmon_/ {print $3; exit}')
      if [[ -n "${asm_sid:-}" ]]; then
        ORACLE_SID="$asm_sid" \
        asm_data_gb=$(asmcmd -p lsdg 2>/dev/null | \
          awk '
            BEGIN{IGNORECASE=1}
            NR==1{
              for(i=1;i<=NF;i++){
                if($i ~ /^Free_MB$/){freeIdx=i}
                if($i ~ /^Name$/){nameIdx=i}
              }
            }
            NR>1 && freeIdx>0 && nameIdx>0 {
              name=$nameIdx; gsub(/\/$/,"",name)
              if (name ~ /DATA/) sum+=$freeIdx
            }
            END{
              if(sum=="") print "N/A"; else printf "%.1f", sum/1024
            }')
      else
        asm_data_gb="N/A"
      fi
    else
      asm_data_gb="N/A"
    fi
  else
    asm_data_gb="N/A"
  fi

  printf "%-15s %-15s %-18s %-17s %-9s %-12s %-10s\n" \
    "$node" "$inst_count" "$hp_free_gb" "$sem_pair" "$sem_pct" "$mem_avail_gb" "$asm_data_gb"
done
