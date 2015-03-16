echo -----------------------------------
echo "1) Prod"
echo "2) Dev"
read d
case "$d" in
  "1") echo "Loading PROD env file..."
        . /u01/oracle/proddb/11.2.0.3/PROD_ebs11.env
        echo "Done.";;
  "2") echo "Loading DEV env file..."
        . /u01/oradev/proddb/11.2.0.3/DEV_ebs11.env
        echo "Done.";;
  *) echo "Wrong arg"
esac
export PS1="(\A)[\u@\h \W] `echo $ORACLE_SID`\$ "

