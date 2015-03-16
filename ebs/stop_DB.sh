#!/bin/bash
#set -x
echo "[info] Stopping DB for $CONTEXT_NAME"
echo "Loading $CONTEXT_NAME env file..."
        .  $ORACLE_HOME/$CONTEXT_NAME.env
        cd $ORACLE_HOME/appsutil/scripts/$CONTEXT_NAME
        ./addbctl.sh stop immediate
        ./addlnctl.sh stop $ORACLE_SID

