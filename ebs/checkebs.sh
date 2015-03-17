#!/bin/bash

function print_text {
printf "\t\t%-20s %s %10s\n" "$1" "||" "$2"
}
echo
echo =================================================================
echo "                        Component's staus                      "
echo =================================================================

#check apps schema availibility
echo "select * from dual;" | sqlplus -s apps/apps > /tmp/start_APP.tmp
TMP_CHK=`cat /tmp/start_APP.tmp | wc -l`
        if [ $TMP_CHK -gt 5 ]; then
        print_text "APPS schema" "Error"
        else
        print_text "APPS schema" "OK"
        fi
#check apps listener
lsnrctl status APPS_$TWO_TASK > /tmp/start_APP.tmp
TMP_CHK=`cat /tmp/start_APP.tmp | grep "Start Date" | wc -l`
        if [ $TMP_CHK -eq 0 ]; then
                print_text "APPS listener" "ERROR"
        else
                print_text "APPS listener" "OK"
        fi
#check db listener
ps -ef | grep tns | grep -w $TWO_TASK >/tmp/start_APP.tmp
TMP_CHK=`cat /tmp/start_APP.tmp | wc -l`
        if [ $TMP_CHK -eq 0 ]; then
                print_text "DB listener" "ERROR"
        else
                print_text "DB listener" "OK"
        fi
#apache web/plsql listener
$COMMON_TOP/admin/scripts/$CONTEXT_NAME/adapcctl.sh status > /tmp/start_APP.tmp
TMP_CHK=`cat /tmp/start_APP.tmp | grep "Apache Web Server Listener :httpd.*is running." | wc -l`
        if [ $TMP_CHK -eq 0 ]; then
                print_text "HTTPD listener" "ERROR"
        else
                print_text "HTTPD listener" "OK"
        fi
TMP_CHK=`cat /tmp/start_APP.tmp | grep "Apache Web Server Listener (PLSQL).*is running." | wc -l`
        if [ $TMP_CHK -eq 0 ]; then
                print_text "PLSQL listener" "ERROR"
        else
                print_text "PLSQL listener" "OK"
        fi
#oracle discoverer


Oracle Discoverer OAD is running as PID 11663

Oracle Discoverer OSAGENT is running as PID 11653

Oracle Discoverer LOCATOR is running as PID 11673

a

