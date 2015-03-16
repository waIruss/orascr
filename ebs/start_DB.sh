#!/bin/bash
#set -x
#!/bin/bash
#set -x
echo "Starting DB for $CONTEXT_NAME"
echo "Loading $CONTEXT_NAME env file..."
        . $ORACLE_HOME/$CONTEXT_NAME.env
        cd $ORACLE_HOME/appsutil/scripts/$CONTEXT_NAME
        ./addbctl.sh start
        ./addlnctl.sh start  $ORACLE_SID
