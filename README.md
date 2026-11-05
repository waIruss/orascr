Purpose

This page defines how SQL against our Oracle databases should be written so that the optimizer can find a good plan, and how to check a query before it goes to production. It covers the most common causes of slow SQL we see in reviews: implicit data type conversion, functions on columns, NOT IN versus NOT EXISTS, selectivity and estimates, bind variables, optional filters, fetching too much, and row-by-row processing.

The standard in one sentence: compare columns with values of the same data type, keep indexed and partition-key columns free of functions, use NOT EXISTS for "rows without a match", give the optimizer correct statistics for skewed and correlated data, use bind variables, fetch only the rows and columns you need, and process data in sets, not row by row. Every new or changed statement on a large table has its plan checked before release.

Applies to Oracle Database 19c/23ai. Related pages: Oracle SQL Hinting, Adaptive Plan Control, SQL Plan Management, Indexes for PK, Unique and FK Constraints, Partitioned Tables.

1. Data types: avoid implicit conversion

When a column and a value have different data types, Oracle converts one of them. If it converts the column, it has to apply a function to every row, so:

an index on that column can't be used for access,
partition pruning on that column doesn't work,
the optimizer's estimate for the predicate becomes a guess,
and in some cases the query fails at runtime.
Comparison	What Oracle does	Effect	Write instead
VARCHAR2 column = number: account_no = 12345	TO_NUMBER(account_no) = 12345	Index not used; ORA-01722 as soon as one row holds a non-numeric value	account_no = '12345'
DATE column ≥ TIMESTAMP bind (typical for Java Timestamp)	INTERNAL_FUNCTION(created_date) >= :1	Index on the date column not used	created_date >= CAST(:ts AS DATE), or bind as DATE
VARCHAR2 column = national character bind (NVARCHAR2)	SYS_OP_C2C(name) = :1	Index not used	Bind as VARCHAR2 in the driver/ORM mapping
DATE column = string: created = '2026-11-05'	TO_DATE using the session's NLS_DATE_FORMAT	Works or fails depending on session settings	created = DATE '2026-11-05' or TO_DATE('2026-11-05', 'YYYY-MM-DD')
NUMBER column = string: id = '42'	id = TO_NUMBER('42') (the value is converted)	Harmless for performance, but hides a type mismatch	id = 42

The rule: the value must match the column's type, never the other way round. Store data in its real type too: numbers as NUMBER, dates as DATE, not as VARCHAR2.

Finding implicit conversions

They're visible in the Predicate Information section of an execution plan as TO_NUMBER("COL"), INTERNAL_FUNCTION("COL") or SYS_OP_C2C("COL") around a column. To find them across the shared pool:

sql
SELECT s.sql_id, s.parsing_schema_name, s.executions,
       ROUND(s.elapsed_time / 1e6) AS elapsed_s,
       p.id AS plan_line, p.operation, p.options, p.object_name,
       NVL(p.access_predicates, p.filter_predicates) AS predicate
FROM   v$sql_plan p
JOIN   v$sql s
       ON s.sql_id = p.sql_id AND s.child_number = p.child_number
WHERE  s.parsing_schema_name NOT IN ('SYS', 'SYSTEM', 'DBSNMP')
AND   (   p.filter_predicates LIKE '%INTERNAL_FUNCTION(%'
       OR p.filter_predicates LIKE '%SYS_OP_C2C(%'
       OR p.filter_predicates LIKE '%TO_NUMBER("%'
       OR p.access_predicates LIKE '%INTERNAL_FUNCTION(%'
       OR p.access_predicates LIKE '%SYS_OP_C2C(%')
ORDER  BY s.elapsed_time DESC;

INTERNAL_FUNCTION also appears for a few other reasons (for example some IN lists), so check each hit in the plan before raising it.

2. Functions on columns

The same mechanism as §1, written explicitly: a function applied to a column prevents index access and partition pruning on that column, and replaces the optimizer's estimate with a fixed guess.

Instead of	Write
TRUNC(created) = :d	created >= :d AND created < :d + 1
TO_CHAR(created, 'YYYY') = '2026'	created >= DATE '2026-01-01' AND created < DATE '2027-01-01'
SUBSTR(code, 1, 3) = 'ABC'	code LIKE 'ABC%'
amount * 1.23 > :limit	amount > :limit / 1.23 (move the arithmetic to the value side)
col1 || col2 = :x	Compare col1 and col2 separately

When a function on the column is unavoidable (for example case-insensitive search with UPPER(last_name) = :name):

create a function-based index on exactly that expression, or a virtual column with a normal index, and
gather statistics on the expression (extended statistics), so the estimate is based on real data rather than a guess.

On partitioned tables this matters twice: TRUNC(partition_key) = :d scans every partition instead of one (see Partitioned Tables).

3. PL/SQL functions called from SQL

A PL/SQL function in a SELECT list or WHERE clause runs once per row, and each call switches between the SQL and PL/SQL engines. On a million rows, that's a million calls.

Two further problems:

Estimates: the optimizer can't know how selective WHERE my_func(col) = 1 is, so it guesses.
Read consistency: if the function runs its own queries, each call sees the data as of its own start, not as of the start of the outer query. Under concurrent changes, the result can mix data from different moments.

Preferred, in this order:

Rewrite as SQL: a join or a CASE expression instead of a lookup function.
Reduce the number of calls: wrap the call in a scalar subquery, (SELECT my_func(col) FROM dual), so Oracle can cache results for repeated input values; mark pure functions DETERMINISTIC.
Reduce the cost per call: PRAGMA UDF in the function, or define it in the statement with WITH FUNCTION (12c+).
4. NOT EXISTS instead of NOT IN

NOT IN and NOT EXISTS look interchangeable, but they give different results when NULLs are involved:

sql
-- Customers without orders
SELECT c.customer_id FROM customers c
WHERE  c.customer_id NOT IN (SELECT o.customer_id FROM orders o);
-- If any ORDERS.CUSTOMER_ID is NULL, this returns NO rows at all.

SELECT c.customer_id FROM customers c
WHERE  NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id);
-- Returns the customers without orders, regardless of NULLs.

Why: x NOT IN (1, 2, NULL) means x <> 1 AND x <> 2 AND x <> NULL, and the last comparison is never true. So one NULL in the subquery makes the whole condition fail for every row.

The standard:

Use NOT EXISTS (or LEFT JOIN ... WHERE b.key IS NULL) for "rows without a match".
Use NOT IN only with a list of literal values, or a subquery on a column declared NOT NULL.
Performance is no longer the main argument: Oracle can run both as an anti-join (HASH JOIN ANTI / ANTI NA in the plan). The reason is correctness.
For IN versus EXISTS, Oracle usually transforms both into the same semi-join. Choose whichever reads more clearly.
5. Selectivity and estimates

Selectivity is the fraction of rows a predicate returns. The optimizer multiplies it by the number of rows to get the estimated row count (cardinality), and almost every plan decision depends on that number:

index access or full scan,
which table to start a join with,
nested loops or hash join,
how much memory a sort or hash join needs.

A correct estimate usually leads to a good plan. A wrong estimate (off by 10× or more) is the most common cause of a bad plan.

When to expect an index to help

An index pays off when the predicate returns a small fraction of the table: typically a few percent or less. The real threshold depends on how well the table's rows are ordered by the index key (the clustering factor). An index on a column with two evenly used values (Y/N) won't help. A full scan is cheaper.

If the column is skewed and queries look for the rare value (e.g. 1% of orders are 'PENDING'):

gather a histogram on the column, so the optimizer knows 'PENDING' is rare, or
index only the rare rows with a function-based index, which keeps the index tiny:
sql
CREATE INDEX orders_pending_ix ON orders (CASE WHEN status = 'PENDING' THEN status END);

SELECT ... FROM orders
WHERE  CASE WHEN status = 'PENDING' THEN status END = 'PENDING';   -- must use the same expression
Common causes of wrong estimates
Cause	Example	Fix
Skewed values, no histogram	status: 99% 'DONE', 1% 'PENDING'	Histogram on the column
Correlated columns	country = 'PL' AND city = 'Warsaw': the optimizer multiplies both selectivities and badly underestimates	Column group statistics: DBMS_STATS.CREATE_EXTENDED_STATS(user, 'ADDRESSES', '(COUNTRY, CITY)')
Function on a column	UPPER(name) = :n	Extended statistics on the expression, or a function-based index (§2)
Value outside the known range	Rows loaded today, statistics from last week	Statistics gathered after large loads; incremental statistics on partitioned tables
Skewed column with bind variables	The first bind value decides the plan for all	Histogram (enables Adaptive Cursor Sharing); see Adaptive Plan Control

How to check: run the statement with the GATHER_PLAN_STATISTICS hint and compare E-Rows (estimated) with A-Rows (actual) in DBMS_XPLAN.DISPLAY_CURSOR(format => 'ALLSTATS LAST') (§10). The first plan line where they differ by 10× or more is where the plan goes wrong.

6. Bind variables

Use bind variables for values that change between executions.

With literals, every distinct value is a different statement:

It's parsed from scratch (a hard parse costs CPU and shared pool locks).
It fills the shared pool with near-identical statements.
It can't be stabilized easily: SQL plan baselines and SQL patches match one exact statement text (see SQL Plan Management).

Literals are acceptable for values that are genuinely constant in the code (status = 'ACTIVE' in a query that always means active rows). For a skewed column with bind variables, rely on a histogram and Adaptive Cursor Sharing rather than going back to literals. CURSOR_SHARING = FORCE is a temporary workaround for applications that can't be changed, not a standard setting.

7. Optional filters ("catch-all" queries)

A single statement that serves every search screen:

sql
WHERE (:p_customer IS NULL OR customer_id = :p_customer)
AND   (:p_status   IS NULL OR status      = :p_status)
AND   (:p_from     IS NULL OR created    >= :p_from)

The statement gets one plan for every combination of filled and empty parameters. That plan has to work when nothing is filled in, so it's usually a full scan, even when the user searched by one customer ID that an index could find instantly.

Build the statement from the filters that are actually given (with bind variables for the values), so each combination gets its own plan. A small number of fixed variants (UNION ALL branches, or separate statements) also works.

8. Fetch only what you need
No SELECT * in application code. Every extra column costs I/O and network, prevents the optimizer from answering from an index alone, and can break the application when a column is added. On wide tables this matters most (see Number of Columns per Table).
Limit rows in the database, not in the application: FETCH FIRST n ROWS ONLY, not fetching everything and discarding most of it.
Paginate by key, not by offset. OFFSET 100000 ROWS FETCH NEXT 50 ROWS ONLY reads and throws away 100,000 rows to return 50, and gets slower with every page. Use the last key of the previous page instead:
sql
  SELECT order_id, created, amount
  FROM   orders
  WHERE  customer_id = :cust
  AND    order_id > :last_order_id_of_previous_page
  ORDER  BY order_id
  FETCH  FIRST 50 ROWS ONLY;
Set the fetch size for large result sets. The Oracle JDBC driver fetches 10 rows per round trip by default, so reading 1 million rows takes 100,000 round trips. Set the fetch size (e.g. 100–1000) for statements that read many rows; other drivers have equivalent settings.
9. Set-based processing and commits

Processing row by row ("slow by slow") is the most expensive way to change data:

sql
-- Row by row: one UPDATE (and often one round trip) per row
FOR r IN (SELECT order_id FROM orders WHERE status = 'NEW' AND created < SYSDATE - 30) LOOP
  UPDATE orders SET status = 'EXPIRED' WHERE order_id = r.order_id;
  COMMIT;
END LOOP;

-- Set-based: one statement
UPDATE orders SET status = 'EXPIRED'
WHERE  status = 'NEW' AND created < SYSDATE - 30;
COMMIT;
Use a single SQL statement where the logic allows it.
Where row-level logic is needed, use BULK COLLECT ... LIMIT and FORALL in PL/SQL, or batch execution in the application (JDBC addBatch), so many rows go in one call.
Commit per logical unit of work, not per row. Every commit waits for redo to be written to disk (log file sync); thousands of commits per second turn that wait into the bottleneck.
10. Checking a query before release

Every new or changed statement on a large table has its plan checked with realistic data volumes:

sql
-- Run the statement once with row-source statistics (allowed diagnostic hint)
SELECT /*+ GATHER_PLAN_STATISTICS */ ...;

-- Then show the plan with estimated vs actual rows
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(NULL, NULL, 'ALLSTATS LAST'));

EXPLAIN PLAN shows only what the optimizer expects to do, and can differ from what runs (it ignores bind values, for example). Use DISPLAY_CURSOR on a real execution.

What to look for:

In the plan	Meaning
E-Rows and A-Rows differ by 10× or more	Misestimate; fix statistics first (§5)
TO_NUMBER("COL"), INTERNAL_FUNCTION("COL"), SYS_OP_C2C("COL") in predicates	Implicit conversion (§1)
Index used only in filter predicates, not in access predicates	The index is read but doesn't narrow the search
TABLE ACCESS FULL on a large table for a query returning few rows	Missing index, function on the column, or conversion
MERGE JOIN CARTESIAN	Usually a missing join condition
PARTITION RANGE ALL where one partition was expected	No pruning: function or conversion on the partition key
High Buffers on a line that returns few rows	Most of the work is reading rows that are then discarded

For long-running statements, Real-Time SQL Monitoring (DBMS_SQLTUNE.REPORT_SQL_MONITOR) shows progress per plan line. It requires the Tuning Pack license.

Hints in application code are a last resort (see Oracle SQL Hinting); for statements already in production, use the tools on the SQL Plan Management page.

11. Review checklist
 Values compared with columns of the same data type; no TO_NUMBER, INTERNAL_FUNCTION or SYS_OP_C2C on columns in the plan.
 Date literals written as DATE 'YYYY-MM-DD' or TO_DATE with an explicit format.
 No functions on indexed or partition-key columns; unavoidable ones backed by a function-based index and extended statistics.
 No per-row PL/SQL lookups where a join would do.
 NOT EXISTS for anti-joins; NOT IN only on literals or NOT NULL columns.
 Histograms and column group statistics where data is skewed or correlated.
 Bind variables for changing values.
 No catch-all (:p IS NULL OR col = :p) queries on large tables.
 No SELECT *; key-based pagination; fetch size set for large reads.
 Set-based DML or bulk operations; commits per unit of work.
 Plan checked with ALLSTATS LAST on realistic data before release.
12. Quick reference: common mistakes
Symptom	Cause
Full scan although the column is indexed	Implicit conversion or function on the column (§1, §2)
ORA-01722 "invalid number" appears after new data arrived	VARCHAR2 column compared with a number; Oracle converts the column
Query on a DATE column slow only from the Java application	Timestamp bind against a DATE column (INTERNAL_FUNCTION)
"Customers without orders" suddenly returns nothing	NOT IN subquery returned a NULL
Query fast in testing, slow in production	Different data volume or skew; estimates wrong; check E-Rows vs A-Rows
Plan good for one customer, terrible for another	Skewed column with bind variables and no histogram
Every page of a list is slower than the previous one	OFFSET pagination
Search screen always does a full scan	Catch-all query with optional filters
Batch job spends its time on log file sync	Commit per row
Report fetches millions of rows very slowly	Default fetch size (10 rows per round trip)
Same query in many versions in the shared pool	Literals instead of bind variables
Query on a partitioned table reads all partitions	Function or conversion on the partition key
