#!/bin/bash

log="fsfo_config.log"

# -------------------------
# Validate TNS
# -------------------------
function validate_tns() {
        local _tns="$1"
        check_tns=$(tnsping "$_tns")

        if [ $? -eq 0 ]; then
                echo "[Info] TNS check passed for: $_tns"
        return 0
        else
                if [[ $check_tns == *"TNS-03505"* ]]; then
                        echo "[Error] Entry for this DB does not exists"
                        return 1
                else
                        echo "[Error] TNS entry $_tns exists but check failed. Please validate tnsnames.ora"
                        echo -e "\n$check_tns"
                        exit 1
                fi
        fi

}

# -------------------------
# Run dgmgrl
# -------------------------

run_dgmgrl() {

    {
        echo
        echo "============================================================"
        echo "[DGMGRL START] $(date '+%Y-%m-%d %H:%M:%S')  DB=$_db"
        echo "============================================================"
        echo
    } | tee -a "$log" >/dev/null

    {
        cat
        echo "EXIT;"
    } | "$ORACLE_HOME/bin/dgmgrl" -echo /@"$_db" 2>&1 \
      | tee -a "$log"

    {
        echo
        echo "============================================================"
        echo "[DGMGRL END]   $(date '+%Y-%m-%d %H:%M:%S')  DB=$_db"
        echo "============================================================"
        echo
    } | tee -a "$log" >/dev/null
}

# -------------------------
# Check connections
# -------------------------
function check_conn {
        tmp_con=$(mktemp)
        # check connections
        for i in $_hh_db $_oe_db; do
                #sqlplus -s /@$i as sysdg << EOF > "$tmp_con" 2>&1
sqlplus -s /@$i as sysdba << EOF > "$tmp_con" 2>&1
WHENEVER SQLERRROR EXIT SQL.SQLCODE
select 1 from dual;
exit;
EOF

                if [ $? -ne 0 ]; then
                        echo "[Error] Connection to $i failed"
                        # print errrors
                        err_con=$(cat $tmp_con)
                        echo -e "\033[2m$err_con\033[0m"
                        rm -f "$tmp_con"
                        exit 1
                else
                        echo "[Info] Connection to $i successful"
                fi
        done
}

# -------------------------
# Configure FSFO
# -------------------------
function configure_fsfo() {
_fsfo_cmds=$(cat <<EOF
EDIT DATABASE $_hh_db SET PROPERTY LogXptMode='FASTSYNC';
EDIT DATABASE $_oe_db SET PROPERTY LogXptMode='FASTSYNC';

EDIT DATABASE $_hh_db SET PROPERTY FastStartFailoverTarget='$__db';
EDIT DATABASE $_oe_db SET PROPERTY FastStartFailoverTarget='$_hh_db';

--EDIT DATABASE $_hh_db SET PROPERTY PreferredObserverHosts='...${_env_lc}...:1,...${_env_lc}...:2';
--EDIT DATABASE $_oe_db SET PROPERTY PreferredObserverHosts='...${_env_lc}....:1,...${_env_lc}...:2';

EDIT CONFIGURATION SET PROPERTY ObserverReconnect=15;
EDIT CONFIGURATION SET PROTECTION MODE AS MaxAvailability;

ENABLE FAST_START FAILOVER;

EDIT DATABASE $_hh_db SET PROPERTY DGConnectIdentifier='$_hh_db';
EDIT DATABASE $_oe_db SET PROPERTY DGConnectIdentifier='$_oe_db';
EOF
)

        echo "[Info] Configuring FSFO for $_db ($_hh_db / $_oe_db, env=$_env)"

_fsfo_output="$(
    run_dgmgrl <<EOF
$_fsfo_cmds
EOF
)"

# Basic error scan
        if echo "$_fsfo_output" | grep -E 'ORA-[0-9]{5}|DGM-[0-9]{5}|SP2-[0-9]{4}|ERROR ' >/dev/null; then
            echo "[Error] DGMGRL reported errors during FSFO configuration for $_db."
            echo "-------- BEGIN DGMGRL OUTPUT --------"
            echo "$_fsfo_output"
            echo "--------- END DGMGRL OUTPUT ---------"
            exit 1
        fi

echo "[Info] FSFO configuration commands executed without detected ORA-/DGM-/SP2-/ERROR."
}

# -------------------------
# Mode CONFIG
# -------------------------
function config() {

        echo ""
        echo "[Info] Creating config for $_db (env: $_env)"

        ## look for current env
        if [[ $_env == "..." ]];then
                file=$(ls ~/ | grep -i "..." |sort -V | tail -n1)
                echo "[Info] Current env file: "$file
        elif [[ $_env == "." ]]; then
                file=$(ls ~/ | grep -iE "^.[0-9]+\.sh$" |sort -V | tail -n1)
                echo "[Info] Current env file: "$file
        elif [[ $_env == "." ]]; then
                file=$(ls ~/ | grep -iE "^.[0-9]+\.sh$" |sort -V | tail -n1)
                echo "[Info] Current env file: "$file
        elif [[ $_env == "." ]]; then
                file=$(ls ~/ | grep -iE "^.[0-9]+\.sh$" |sort -V | tail -n1)
                echo "[Info] Current env file: "$file
        fi

        ## check if file exists
        if [[ -z "${file:-}" ]]; then
            echo "[ERROR]: Environment file does not exists. Please check environment."
            exit 1
        fi

        ## source env
        source "$HOME/$file"
        echo "[Info] Current TNS location: $TNS_ADMIN"
        #_hh_db="${_db::-1}h"
        #_oe_db="${_db::-1}o"
        _hh_db="${_db::-1}1"
        _oe_db="${_db::-1}2"

        #xtract lifecuce
        _env_lc="${_hh_db: -3:1}"
#       case "$_env_lc" in
#               d|p|s)
#               ;;
#               t)
#               _env_lc="d"
#               ;;
#               *)

       case "$_env_lc" in
               p|s)
               ;;
               t)
               _env_lc="d"
                ;;
               d)
               _env_lc="t"
               ;;
               *)

        echo "[Error] Invalid or nor supported value for environment: $_env_lc"
        exit 1
        ;;
        esac

        echo "[Info] . DB Name: $_hh_db"
        echo "[Info] . DB Name: $_oe_db"


        declare -A tns_results

        # validate TNS
        for i in $_hh_db $_oe_db; do
                echo "[Info] Validating TNS entry for $i..."
                validate_tns "$i"
                tns_results["$i"]=$?
        done

        # if both are ok
        if [[ ${tns_results[$_hh_db]} -eq 0 && ${tns_results[$_oe_db]} -eq 0 ]]; then
                echo "[Info] TNS checked passed for both DB. Contiuning"
        else
                echo "[Error] TNS checked for at least one DB."
        fi

        check_conn

        # check if FSFO not already configured

dg_output="$(run_dgmgrl <<EOF
show fast_start failover;
EOF
)"

# temp disable
#       if echo "$dg_output" | grep -q "Fast-Start Failover: Enabled"; then
#               echo "[ERROR]: Fast-Start Failover is already enabled"
#               exit 1
#       fi

        echo "[Info] Fast-Start Failover is not enabled, continuing..."

        configure_fsfo
}

# -------------------------
# Mode DECONFIG
# -------------------------
#function deconfig() {
#    echo "Undoing step A"
#    echo "Undoing step B"
#}


# -------------------------
# Help
# -------------------------
function show_help() {
cat <<EOF
Usage:
  $0 --config --env <ENV> --dbname <DB_NAME>
  $0 --deconfig --dbname <DB_NAME>

Options:
  --config            Create configuration
  --deconfig          Remove configuration
  --env <env>         Environment (required with --config)
                      Allowed: . | . | . | .
  --dbname <name>     Database name (required)
  --help              Show this help

Examples:
  $0 --config --env . --dbname b1234d1h
  $0 --deconfig --dbname b1234d1h
EOF
}

# -------------------------
# Argument parsing
# -------------------------
_mode=""
_db=""
_env=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            _mode="config"
            shift
            ;;
        --deconfig)
            _mode="deconfig"
            shift
            ;;
        --dbname)
            if [[ -z "${2-}" || "$2" == -* ]]; then
                echo "ERROR: --dbname requires a value"
                show_help
                exit 1
            fi
            _db="$2"
            shift 2
            ;;
        --env)
            if [[ -z "${2-}" || "$2" == -* ]]; then
                echo "ERROR: -env requires a value (.|.|.|.)"
                show_help
                exit 1
            fi
            _env="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option $1"
            show_help
            exit 1
            ;;
    esac
done

[[ -z "$_mode" ]] && { echo "ERROR: --config or --deconfig required"; show_help; exit 1; }
[[ -z "$_db"   ]] && { echo "ERROR: --dbname required"; show_help; exit 1; }

# validate env
if [[ "$_mode" == "config" ]]; then
    if [[ -z "$_env" ]]; then
        echo "ERROR: -env is required when using --config"
        show_help
        exit 1
    fi

    case "$_env" in
        |||)
            ;;
        *)
            echo "ERROR: Invalid -env value '$_env'. Allowed: , , , "
            show_help
            exit 1
            ;;
    esac
fi

if [[ "$_mode" == "config" ]]; then
    _host_short="$(hostname -s)"
    case "$_host_short" in
        is-|is-|is-)
            ;;
        *)
            echo "[Error] CONFIG mode can only be executed on is-, is-, or is-."
            echo "[Error] Current host: $_host_short"
            exit 1
            ;;
    esac
fi

"$_mode"


exit 1

-------------

