set echo off
set feedback on
set linesize 500
col sid format 99999
col serial format 999
col username format a10
col osuser format a10
col owner format a10
col object_name format a30
col machine format a15
col program format a35
col lockmode format a10

set echo off
col sid form 9999
col id1 form 9999999999
col id2 form 999999999
col lmode head "Lock Held" form a14
col request1 head "Lock Request" form a16
col type head "Lock Type" form a15
col ctime head "Time|Held" form 999999999
col block head "No Of |Sessions|Waiting|For This|Lock" form 99999
SELECT sid,
         DECODE (
            TYPE,
            'BL', 'Buffer hash table',
            'CF', 'Control File Transaction',
            'CI', 'Cross Instance Call',
            'CS', 'Control File Schema',
            'CU', 'Bind Enqueue',
            'DF', 'Data File',
            'DL', 'Direct-loader index-creation',
            'DM', 'Mount/startup db primary/secondary instance',
            'DR', 'Distributed Recovery Process',
            'DX', 'Distributed Transaction Entry',
            'FI', 'SGA Open-File Information',
            'FS', 'File Set',
            'IN', 'Instance Number',
            'IR', 'Instance Recovery Serialization',
            'IS', 'Instance State',
            'IV', 'Library Cache InValidation',
            'JQ', 'Job Queue',
            'KK', 'Redo Log "Kick"',
            'LS', 'Log Start/Log Switch',
            'MB', 'Master Buffer hash table',
            'MM', 'Mount Definition',
            'MR', 'Media Recovery',
            'PF', 'Password File',
            'PI', 'Parallel Slaves',
            'PR', 'Process Startup',
            'PS', 'Parallel Slaves Synchronization',
            'RE', 'USE_ROW_ENQUEUE Enforcement',
            'RT', 'Redo Thread',
            'RW', 'Row Wait',
            'SC', 'System Commit Number',
            'SH', 'System Commit Number HWM',
            'SM', 'SMON',
            'SQ', 'Sequence Number',
            'SR', 'Synchronized Replication',
            'SS', 'Sort Segment',
            'ST', 'Space Transaction',
            'SV', 'Sequence Number Value',
            'TA', 'Transaction Recovery',
            'TD', 'DDL enqueue',
            'TE', 'Extend-segment enqueue',
            'TM', 'DML enqueue',
            'TS', 'Temporary Segment',
            'TT', 'Temporary Table',
            'TX', 'Transaction',
            'UL', 'User-defined Lock',
            'UN', 'User Name',
            'US', 'Undo Segment Serialization',
            'WL', 'Being-written redo log instance',
            'WS', 'Write-atomic-log-switch global enqueue',
            'XA', 'Instance Attribute',
            'XI', 'Instance Registration',
            DECODE (SUBSTR (TYPE, 1, 1),
                    'L', 'Library Cache (' || SUBSTR (TYPE, 2, 1) || ')',
                    'N', 'Library Cache Pin (' || SUBSTR (TYPE, 2, 1) || ')',
                    'Q', 'Row Cache (' || SUBSTR (TYPE, 2, 1) || ')',
                    '????'))
            TYPE,
         id1 obj_id, B.OWNER, B.OBJECT_NAME, B.OBJECT_TYPE,
         id2,
         DECODE (lmode,
                 0, 'None(0)',
                 1, 'Null(1)',
                 2, 'Row Share(2)',
                 3, 'Row Exclu(3)',
                 4, 'Share(4)',
                 5, 'Share Row Ex(5)',
                 6, 'Exclusive(6)')
            lmode,
         DECODE (request,
                 0, 'None(0)',
                 1, 'Null(1)',
                 2, 'Row Share(2)',
                 3, 'Row Exclu(3)',
                 4, 'Share(4)',
                 5, 'Share Row Ex(5)',
                 6, 'Exclusive(6)')
            request1,
         ctime,
         block
    FROM v$lock a, dba_OBJECTS B
    WHERE A.ID1 = B.OBJECT_ID
   AND TYPE NOT IN ('MR', 'RT')
ORDER BY DECODE (request, 0, 0, 2), block, 5
/

