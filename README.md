WITH params AS (
  SELECT 0.10 AS pct_free,        -- assumed PCTFREE (fill target after rebuild), must be <= 0.25
         1    AS min_reclaim_mb   -- noise floor; use ~100+ in prod
  FROM dual
),
seg AS (
  SELECT a.owner, a.segment_name, a.partition_name, a.bytes,
         a.fs1_bytes, a.fs2_bytes, a.fs3_bytes, a.fs4_bytes, a.full_bytes,
         a.fs1_blocks + a.fs2_blocks + a.fs3_blocks + a.fs4_blocks AS nonfull_blocks,
         a.full_blocks,
         -- block size derived per row (handles non-default block size tablespaces)
         a.unformated_blocks *
           NVL( (a.fs1_bytes + a.fs2_bytes + a.fs3_bytes + a.fs4_bytes + a.full_bytes)
                / NULLIF(a.fs1_blocks + a.fs2_blocks + a.fs3_blocks + a.fs4_blocks + a.full_blocks, 0)
              , 8192)                                                AS unfmt_bytes,
         NVL(ds.initial_extent, 65536)                               AS initial_extent
  FROM   dba_maintenance.dbaas_coe_segment_space_analyses a
  LEFT JOIN dba_segments ds
         ON  ds.owner        = a.owner
         AND ds.segment_name = a.segment_name
         AND ds.segment_type = a.segment_type
         AND NVL(ds.partition_name, '~') = NVL(a.partition_name, '~')
  WHERE  a.segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
  AND    a.segment_subtype = 'ASSM'
  -- AND a.<analysis_time/run_id> = (SELECT MAX(...) FROM ...)   -- if the table keeps history
),
calc AS (
  SELECT s.*,
         -- free space inside blocks, minus what PCTFREE would leave after rebuild
         -- FS1 effectively spans PCTFREE..25% (below PCTFREE ASSM marks the block FULL)
           GREATEST((0.25  - p.pct_free) / 2, 0) * s.fs1_bytes
         + GREATEST( 0.375 - p.pct_free,      0) * s.fs2_bytes
         + GREATEST( 0.625 - p.pct_free,      0) * s.fs3_bytes
         + GREATEST( 0.875 - p.pct_free,      0) * s.fs4_bytes          AS frag_bytes,
         GREATEST(s.bytes - s.fs1_bytes - s.fs2_bytes - s.fs3_bytes - s.fs4_bytes
                  - s.full_bytes - s.unfmt_bytes, 0)                    AS above_hwm_bytes
  FROM   seg s CROSS JOIN params p
),
seg_reclaim AS (
  -- a segment cannot shrink/move below its INITIAL extent
  SELECT c.*,
         GREATEST(LEAST(c.frag_bytes + c.unfmt_bytes + c.above_hwm_bytes,
                        c.bytes - c.initial_extent), 0)                 AS reclaim_bytes
  FROM   calc c
)
SELECT owner,
       segment_name                                                     AS table_name,
       COUNT(*)                                                         AS segs,
       ROUND(SUM(bytes)           / 1048576, 1)                         AS alloc_mb,
       ROUND(SUM(frag_bytes)      / 1048576, 1)                         AS frag_free_mb,
       ROUND(SUM(unfmt_bytes)     / 1048576, 1)                         AS unformatted_mb,
       ROUND(SUM(above_hwm_bytes) / 1048576, 1)                         AS above_hwm_mb,
       ROUND(SUM(reclaim_bytes)   / 1048576, 1)                         AS est_reclaim_mb,
       ROUND(100 * SUM(reclaim_bytes) / NULLIF(SUM(bytes), 0), 1)       AS waste_pct,
       ROUND(100 * SUM(nonfull_blocks)
                 / NULLIF(SUM(nonfull_blocks + full_blocks), 0), 2)     AS nonfull_blk_pct
FROM   seg_reclaim
GROUP  BY owner, segment_name
HAVING SUM(reclaim_bytes) >= (SELECT min_reclaim_mb * 1048576 FROM params)
ORDER  BY SUM(reclaim_bytes) DESC, SUM(bytes) DESC
FETCH FIRST 30 ROWS ONLY;
