#!/bin/bash

# 11.5 cd $COMMON_TOP/admin/scripts/$CONTEXT_NAME
# 12.1 cd $INST_TOP/admin/scripts

#!/bin/bash
echo "[info] Stopping apps for context_name $CONTEXT_NAME"
echo "[info] Loading $CONTEXT_NAME env file..."
        . $APPL_TOP/APPS$CONTEXT_NAME.env
        $COMMON_TOP/admin/scripts/$CONTEXT_NAME/adstpall.sh apps/apps

