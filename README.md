# executes query in a loop
# as an example query for identifiing db role by agent

#!/bin/bash

out_file="sql_result.out"
#export ORACLE_SID=$1
#export ORAENV_ASK=NO

#. oraenv
#. oraenv > /dev/null 2>&1

while true
do
        TS=$(date "+%y-%m-%d %H:%M:%S")
        RESULT=$(sqlplus -s / as sysdba <<EOF
set heading off feedback off pagesize 0 verify off echo off
var rc refcursor

DECLARE
  dgStatus v\$database.database_role%TYPE;
  countDgpdb number;
  countStatus number;
  countOther number;
  countRemoteConfig number;
  database_role v\$database.database_role%TYPE;
  fs_failover_status v\$database.fs_failover_status%TYPE;
  dbUniqueName v\$database.db_unique_name%TYPE;
  TYPE data_cursor_type IS REF CURSOR;
 data_cursor data_cursor_type;
 cdb v\$database.cdb%TYPE;
 dbStatus VARCHAR2(12);
 dgBrokerInfo VARCHAR2(50);
BEGIN
dgStatus:='None';
select upper(status) into dbStatus from v\$instance;
IF dbStatus <> 'STARTED' THEN
BEGIN
  SELECT count(*) INTO countOther FROM v\$DG_BROKER_CONFIG
   WHERE UPPER(dataguard_role) = 'OTHER';
  SELECT count(*) INTO countRemoteConfig FROM v\$DG_BROKER_CONFIG
   WHERE UPPER(dataguard_role) LIKE 'REMOTE CONFIG MEMBER';
  BEGIN
    EXECUTE IMMEDIATE 'SELECT count(*) FROM X\$DRC WHERE lower(attribute) = ''role'' AND UPPER(value) = ''PLUGGABLE_DATABASE''' INTO countDgpdb;
  EXCEPTION
     WHEN OTHERS THEN
       countDgpdb := 0;
  END;
  dgBrokerInfo := SYS.DBMS_DRS.DG_BROKER_INFO('remote_config');
  SELECT cdb INTO cdb FROM v\$database;
EXCEPTION
  WHEN OTHERS
    THEN
     NULL;
END;
IF ( (countOther > 0 ) OR (countDgpdb > 0) OR (countRemoteConfig > 0 ) OR (UPPER(dgBrokerInfo) = 'YES') ) THEN
  dgStatus := 'DGPDB_PRIMARY';
ELSE
  select upper(DATABASE_ROLE), upper(fs_failover_status), db_unique_name, cdb into database_role, fs_failover_status, dbUniqueName, cdb from v\$database;
  IF (INSTR (database_role, 'STANDBY') <> 0 OR database_role = 'FAR SYNC' OR (database_role = 'PRIMARY' AND (fs_failover_status <> 'DISABLED' AND
  fs_failover_status <> 'REINSTATE REQUIRED' AND fs_failover_status <> 'REINSTATE FAILED' AND fs_failover_status <> 'TARGET OVER LAG LIMIT' AND fs_failover_status <> 'TARGET UNDER LAG LIMIT')))  THEN
     dgStatus:=initcap(database_role);
  ELSE
     SELECT COUNT(*) into countStatus FROM v\$archive_dest_status WHERE type IN ('PHYSICAL', 'LOGICAL', 'SNAPSHOT', 'FAR SYNC');
     IF countStatus > 0 THEN
       dgStatus:=initcap(database_role);
     ELSE
       SELECT COUNT(*) into countStatus FROM v\$archive_dest_status WHERE type IN ('OAM', 'AVM', 'BACKUP APPLIANCE', 'RECOVERY APPLIANCE');
        IF countStatus > 0 THEN
            dgStatus:='DBLRA_PROTECTED';
        ELSE
          BEGIN
               EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM v\$dg_broker_config dg, v$database db WHERE upper(dg.DATABASE) = upper(:name)
                           AND DATAGUARD_ROLE=''PRIMARY'' AND ENABLED=''TRUE'' AND db.open_mode!=''MOUNTED''' into countStatus using dbUniqueName;
                IF countStatus > 0 THEN
                 dgStatus:=initcap(database_role);
                ELSE
                                  select count(*) into countStatus from v\$database where fs_failover_status = 'REINSTATE REQUIRED' and open_mode = 'MOUNTED';
                 IF countStatus > 0 THEN
                   dgStatus:='RE_EVALUATE';
                 ELSE
                   select count(*) into countStatus from v\$database where open_mode = 'MOUNTED' and primary_db_unique_name is not null;
                   IF countStatus > 0 THEN
                     dgStatus:='RE_EVALUATE';
                   ELSE
                     NULL;
                   END IF;
                 END IF;
                END IF;
           EXCEPTION WHEN OTHERS THEN
           select count(*) into countStatus from v\$database where fs_failover_status = 'REINSTATE REQUIRED' and open_mode = 'MOUNTED';
                 IF countStatus > 0 THEN
                   dgStatus:='RE_EVALUATE';
                 ELSE
                   select count(*) into countStatus from v\$database where open_mode = 'MOUNTED' and primary_db_unique_name is not null;
                   IF countStatus > 0 THEN
                     dgStatus:='RE_EVALUATE';
                   ELSE
                     NULL;
                   END IF;
                 END IF;
           END ;
        END IF ;
     END IF ;
   END IF ;
 END IF;
ELSE
 dgStatus:='RE_EVALUATE';
END IF;
open data_cursor for select dgStatus, cdb from dual;
   :rc := data_cursor;
END ;
/
print rc


set linesize 200
col destination format a60
select a.dest_id, a.status, a.target, a.register, a.destination, b.type
 from v\$archive_dest a,
 v\$archive_dest b
 where a.dest_id = b.dest_id;

select FS_FAILOVER_STATUS, database_role from v$database;

exit
EOF
)

echo "$TS | $RESULT" >> "$out_file"
sleep 2
done


================================
OLD VERSION
================================
#!/bin/bash

out_file="sql_result.out"
export ORACLE_SID=$1
export ORAENV_ASK=NO

. oraenv
#. oraenv > /dev/null 2>&1

while true
do
        TS=$(date "+%y-%m-%d %H:%M:%S")
        RESULT=$(sqlplus -s / as sysdba <<EOF
set heading off feedback off pagesize 0 verify off echo off
select
   case
   when
      ((
      (
         select
            count(*)
         from
            v\$archive_dest        d,
            v\$archive_dest_status s
         where
            d.dest_id     =s.dest_id
            and d.target  ='STANDBY'
            and d.register='YES'
            and (
               s.type    !='OAM'
               and s.type!='AVM'
               and s.type!='BACKUP APPLIANCE'
               and s.type!='RECOVERY APPLIANCE')) > 0)
      OR (
         database_role like '%STANDBY')
      OR (
         database_role          ='PRIMARY'
         AND FS_FAILOVER_STATUS != 'DISABLED'))
   then
      initcap(database_role)
   when
      (
      (
         select
            count(*)
         from
            v\$archive_dest_status
         where
            type in ('OAM',
                     'AVM',
                     'BACKUP APPLIANCE',
                     'RECOVERY APPLIANCE')) > 0)
   then
      'DBLRA_PROTECTED'
   else
      'None'
   end  "DataGuardStatus",
   'NO' "CDB"
from
   v\$database;

set linesize 200
col destination format a60
select a.dest_id, a.status, a.target, a.register, a.destination, b.type
 from v\$archive_dest a,
 v\$archive_dest b
 where a.dest_id = b.dest_id;

select FS_FAILOVER_STATUS, database_role from v\$database;

exit
EOF
)

echo "$TS | $RESULT" >> "$out_file"
sleep 3
done

select /*+ ordered */ w1.sid waiting_session, h1.sid holding_session, w.kgllktype lock_or_pin, w.kgllkhdl address, decode(h.kgllkmod, 0, 'None', 1, 'Null', 2, 'Share', 3, 'Exclusive', 'Unknown') mode_held, decode(w.kgllkreq, 0, 'None', 1, 'Null', 2, 'Share', 3, 'Exclusive', 'Unknown') mode_requested
from dba_kgllock w, dba_kgllock h, v$session w1, v$session h1
where
(((h.kgllkmod != 0) and (h.kgllkmod != 1)
and ((h.kgllkreq = 0) or (h.kgllkreq = 1)))
and
(((w.kgllkmod = 0) or (w.kgllkmod= 1))
and ((w.kgllkreq != 0) and (w.kgllkreq != 1))))
and w.kgllktype = h.kgllktype
and w.kgllkhdl = h.kgllkhdl
and w.kgllkuse = w1.saddr
and h.kgllkuse = h1.saddr




============

online solution wydaj sie nie pomgac bedzie trzeba uruchomic catproc i a wczesnie startuo upgrade 
 
SQL>@$ORACLE_HOME/rdbms/admin/dbmsaqds.plb --> creates package
SQL>@$ORACLE_HOME/rdbms/admin/prvtaqds.plb -- >creates package body
 
If SYS.DBMS_AQADM_SYS is still invalid, run catalog.sql/catproc.sql/utlrp.sql
 
SQL>shutdown immediate
SQL>startup upgrade
 
SQL>@?/rdbms/admin/catalog.sql
SQL>@?/rdbms/admin/catproc.sql
SQL>@?/rdbms/admin/utlrp.sql
-- again
SQL>@?/rdbms/admin/utlrp.sql
