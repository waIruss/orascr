select name, state, round(total_mb/1024) "Total GB" , round(free_mb/1024) "Free GB" from v$asm_diskgroup
order by 1 asc;



