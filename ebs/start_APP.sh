#!/bin/bash

# 11.5 cd $COMMON_TOP/admin/scripts/$CONTEXT_NAME
# 12.1 cd $COMMON_TOP/admin/scripts/PROD_ebs11

echo "[info] Starting apps for context_name $CONTEXT_NAME"
echo "[info] Start APPS tier only if DB is reachable"
echo "[info] Trying to connect to the database"
echo "[info] Loading $CONTEXT_NAME env file..."
        . $APPL_TOP/APPS$CONTEXT_NAME.env
	echo "select * from dual;" | sqlplus -s apps/apps > /tmp/start_APP.tmp
        TPM_CHK=`cat /tmp/start_APP.tmp | wc -l`
        echo "TPM_CHK: $TPM_CHK"

        if [ $TPM_CHK -gt 5 ]; then
                echo " >>> Failed to reach DB"
        else
                echo "Reached DB. OK. Continuing with APPS startup."
        fi
        $COMMON_TOP/admin/scripts/$CONTEXT_NAME/adstrtal.sh apps/apps

