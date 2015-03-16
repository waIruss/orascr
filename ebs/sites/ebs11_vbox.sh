#!/bin/bash
echo "1) Prod"
echo "2) Dev"
read d
case "$d" in
  "1") echo "Loading PROD env file..."
        . /u01/oracle/prodappl/APPSPROD_ebs11.env
        echo "Done.";;
  "2") echo "Loading DEV env file..."
        . /u01/oradev/prodappl/APPSDEV_ebs11.env
        echo "Done.";;
  *) echo "Wrong arg"
esac
export PS1="(\A)[\u@\h \W] `echo $CONTEXT_NAME`\$ "
