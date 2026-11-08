{#- Health check report for one database and one run.
    Inputs (set by the role): results, conn_ok, conn_error, db_info, desc_files, database_tnsname, database_user,
    run_timestamp, run_id, script_timeout, html_max_log_kb, awr_days.
    Charts: every script in section 'Trends' whose output follows the CHART contract (see add_trend_scripts.sh)
    is parsed below into `charts`; the KPI tiles and the included trends.html.j2 both use it. -#}

{#- ---------- tunables ---------- -#}
{%- set thr = {'load_pct': [70, 100], 'host_cpu': [80, 95], 'commit_ms': [5, 15]} %}{#- [watch, high] -#}
{%- set table_sections = ['SystemOverview', 'InstanceInfo'] %}

{#- ---------- helpers ---------- -#}
{%- macro slug(s) -%}det-{{ s | lower | regex_replace('[^a-z0-9]+', '-') }}{%- endmacro -%}{#- anchor of a section's detail panels -#}
{%- macro human(s) -%}{{ s | regex_replace('([a-z])([A-Z])', '\\1 \\2') }}{%- endmacro -%}
{%- macro cmax(c, idxs) -%}{#- highest numeric value in the given columns of a parsed chart, '' if none -#}
{%-   set m = namespace(v=none) -%}
{%-   for row in c.rows -%}
{%-     for i in idxs -%}
{%-       if row[i] is defined and row[i] | trim not in ['', '-'] -%}
{%-         set x = row[i] | float -%}
{%-         if m.v is none or x > m.v %}{% set m.v = x %}{% endif -%}
{%-       endif -%}
{%-     endfor -%}
{%-   endfor -%}
{{-   '' if m.v is none else m.v -}}
{%- endmacro -%}
{%- macro tile(label, value, unit, sub, level='', flag='') -%}
<div class="kpi{{ ' ' ~ level if level }}">
  <div class="k">{{ label }}</div>
  <div class="v">{{ value }}{% if unit and value != '–' %}<small> {{ unit }}</small>{% endif %}</div>
  <div class="s">{{ sub }}</div>
  {%- if flag %}<div class="flag">{{ flag }}</div>{% endif %}
</div>
{%- endmacro -%}

{#- ---------- derived data ---------- -#}
{%- set counts = {} -%}
{%- for s in ['OK', 'ERRORS', 'FAILED', 'TIMEOUT'] -%}
{%-   set _ = counts.update({s: results | selectattr('status', 'equalto', s) | list | length}) -%}
{%- endfor -%}
{%- set n_total = results | length %}
{%- set bad = results | rejectattr('status', 'equalto', 'OK') | list %}
{%- if not conn_ok %}{% set verdict = 'FAILED' %}
{%- elif counts.FAILED %}{% set verdict = 'FAILED' %}
{%- elif counts.TIMEOUT %}{% set verdict = 'TIMEOUT' %}
{%- elif counts.ERRORS %}{% set verdict = 'ERRORS' %}
{%- else %}{% set verdict = 'OK' %}{% endif %}
{%- if not conn_ok %}{% set sentence = 'Could not connect, no checks were run' %}
{%- elif not bad %}{% set sentence = 'All ' ~ n_total ~ ' checks passed' %}
{%- else %}{% set sentence = (bad | length) ~ ' of ' ~ n_total ~ ' checks ' ~ ('needs' if bad | length == 1 else 'need') ~ ' attention' %}{% endif %}
{%- set bad_txt = [(counts.ERRORS ~ ' with errors') if counts.ERRORS else '', (counts.FAILED ~ ' failed') if counts.FAILED else '',
                   (counts.TIMEOUT ~ ' timed out') if counts.TIMEOUT else ''] | select | join(', ') %}
{%- set run_ts = (run_timestamp[:10] ~ ' ' ~ run_timestamp[11:] | replace('-', ':')) if run_timestamp | length == 19 else run_timestamp %}
{%- set dbi = db_info if db_info is mapping else {} %}

{%- set sec = namespace(names=[]) %}
{%- for r in results %}{% if r.section not in sec.names %}{% set sec.names = sec.names + [r.section] %}{% endif %}{% endfor %}

{%- set descs = {} %}
{%- for d in (desc_files | default({})).results | default([]) %}
{%-   set _ = descs.update({d.item.sql_file: (d.content | default('') | b64decode)}) %}
{%- endfor %}

{%- set ch = namespace(list=[]) %}
{%- for r in results if r.section == 'Trends' %}
{%-   set ln = namespace(data=[]) %}
{%-   for l in (r.output | default('')).splitlines() | map('trim') %}
{%-     if (ln.data or l.startswith('CHART|')) and '|' in l %}{% set ln.data = ln.data + [l] %}{% endif %}
{%-   endfor %}
{%-   if ln.data | length > 2 %}
{%-     set meta = ln.data[0].split('|') %}
{%-     set ch.list = ch.list + [{'script': r.script, 'status': r.status, 'short_desc': r.short_desc, 'ok': true,
                                 'type': meta[1] | default('line'), 'title': meta[2] | default(r.short_desc),
                                 'vtitle': meta[3] | default(''), 'cols': ln.data[1].split('|'),
                                 'rows': ln.data[2:] | map('split', '|') | list}] %}
{%-   else %}
{%-     set ch.list = ch.list + [{'script': r.script, 'status': r.status, 'short_desc': r.short_desc, 'ok': false}] %}
{%-   endif %}
{%- endfor %}
{%- set charts = ch.list %}

{#- KPI values from the trend charts (missing chart = '–') -#}
{%- set c_aas  = charts | selectattr('script', 'equalto', 'trend_aas')      | selectattr('ok') | list | first | default(none) %}
{%- set c_host = charts | selectattr('script', 'equalto', 'trend_host_cpu') | selectattr('ok') | list | first | default(none) %}
{%- set c_lat  = charts | selectattr('script', 'equalto', 'trend_latency')  | selectattr('ok') | list | first | default(none) %}
{%- set k_load = (cmax(c_aas, [1]) | trim) if c_aas else '' %}
{%- set k_cpu  = (c_aas.rows[-1][3] | default('') | trim) if c_aas else '' %}
{%- set k_host = (cmax(c_host, range(1, c_host.cols | length) | list) | trim) if c_host else '' %}
{%- set k_lfs  = (cmax(c_lat, [c_lat.cols.index('log file sync')]) | trim) if c_lat and 'log file sync' in c_lat.cols else '' %}
{%- set load_pct = ((k_load | float) / (k_cpu | float) * 100) if k_load and k_cpu | float > 0 else none %}
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{ database_tnsname }} health check {{ run_ts }}</title>
<style>
  :root {
    --ink: #1d2430; --ink-2: #3b4452; --muted: #5b6573; --line: #dde1e6; --line-2: #eceef1; --tint: #f6f7f9;
    --red: #b42318; --red-bg: #fde8e6; --amber: #8a5a00; --amber-bg: #fff4d6; --green: #1e7a3d; --green-bg: #e3f4e8;
    --mono: ui-monospace, "Cascadia Mono", Consolas, monospace;
  }
  * { box-sizing: border-box; }
  html { scroll-padding-top: 64px; }
  body { margin: 0; color: var(--ink); background: #fff; font: 15px/1.5 "Segoe UI", system-ui, -apple-system, Roboto, sans-serif; }
  .wrap { max-width: 1240px; margin: 0 auto; padding: 0 24px; }
  a { color: #1c5cab; }
  :focus-visible { outline: 2px solid #2a78d6; outline-offset: 2px; border-radius: 4px; }

  /* top bar */
  .topbar { position: sticky; top: 0; z-index: 10; background: rgba(255, 255, 255, .96); border-bottom: 1px solid var(--line); }
  .topbar .wrap { display: flex; align-items: center; gap: 18px; height: 52px; }
  .topbar .name { display: flex; align-items: center; gap: 8px; font-size: 16px; font-weight: 700; white-space: nowrap; }
  .topbar nav { display: flex; gap: 2px; flex: 1; overflow-x: auto; }
  .topbar nav a { color: var(--ink-2); text-decoration: none; font-size: 14px; padding: 5px 10px; border-radius: 6px; white-space: nowrap; }
  .topbar nav a:hover { background: var(--tint); }
  .actions { display: flex; gap: 6px; }
  button { font: inherit; font-size: 13px; color: var(--ink-2); background: #fff; border: 1px solid var(--line);
           border-radius: 6px; padding: 4px 10px; cursor: pointer; white-space: nowrap; }
  button:hover { background: var(--tint); }

  /* verdict band */
  .verdict { margin: 28px 0 16px; border: 1px solid var(--line); border-left: 6px solid var(--v); border-radius: 10px; overflow: hidden; }
  .v-OK     { --v: var(--green); --vbg: var(--green-bg); --vline: #bfe3c9; }
  .v-ERRORS { --v: #d29b00;      --vbg: var(--amber-bg); --vline: #f1dfa6; }
  .v-FAILED, .v-TIMEOUT { --v: var(--red); --vbg: var(--red-bg); --vline: #f5c6c0; }
  .v-head { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 18px 24px;
            background: var(--vbg); border-bottom: 1px solid var(--vline); }
  .verdict h1 { margin: 0; font-size: 38px; line-height: 1.15; font-weight: 700; letter-spacing: -.02em; overflow-wrap: anywhere; }
  .v-head .badge { background: #fff; box-shadow: inset 0 0 0 1px var(--vline); }
  .v-body { padding: 14px 24px 18px; }
  .v-sentence { margin: 0; font-size: 20px; font-weight: 600; color: var(--ink-2); }
  .v-att { margin: 10px 0 0; font-size: 14px; color: var(--ink-2); }
  .v-att a { margin-right: 12px; }
  .facts { display: flex; flex-wrap: wrap; gap: 10px 40px; margin: 16px 0 0; padding-top: 14px; border-top: 1px solid var(--line-2); }
  .facts div { min-width: 0; }
  .facts dt { font-size: 13px; color: var(--muted); }
  .facts dd { margin: 0; font-weight: 600; overflow-wrap: anywhere; }
  .facts dd.nowrap { white-space: nowrap; }

  /* KPI strip */
  .kpis { display: grid; grid-template-columns: repeat(5, 1fr); gap: 1px; background: var(--line-2);
          border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
  .kpi { background: #fff; padding: 14px 18px 16px; }
  .kpi .k { font-size: 13px; color: var(--muted); }
  .kpi .v { font-size: 26px; font-weight: 600; line-height: 1.25; }
  .kpi .v small { font-size: 15px; font-weight: 400; color: var(--muted); }
  .kpi .s { font-size: 13px; color: var(--muted); }
  .kpi .flag { display: inline-block; margin-top: 6px; padding: 1px 9px; border-radius: 999px; font-size: 12px; font-weight: 600; }
  .kpi.warn { box-shadow: inset 0 3px #d29b00; } .kpi.warn .flag { background: var(--amber-bg); color: var(--amber); }
  .kpi.crit { box-shadow: inset 0 3px var(--red); } .kpi.crit .flag { background: var(--red-bg); color: var(--red); }

  /* headings, tables */
  h2 { font-size: 20px; font-weight: 600; margin: 44px 0 12px; padding-bottom: 8px; border-bottom: 1px solid var(--line); }
  h2 .count { margin-left: 8px; font-size: 14px; font-weight: 400; color: var(--muted); }
  h3 { font-size: 16px; font-weight: 600; margin: 22px 0 8px; }
  .tablewrap { overflow-x: auto; border: 1px solid var(--line); border-radius: 8px; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th, td { padding: 7px 12px; text-align: left; vertical-align: top; border-bottom: 1px solid var(--line-2); }
  tbody tr:last-child td { border-bottom: 0; }
  thead th { font-size: 13px; font-weight: 600; color: var(--muted); border-bottom: 1px solid var(--line); white-space: nowrap; }
  .c { text-align: center; } .r { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .summary tr.group th { color: var(--muted); font-size: 13px; padding: 12px 12px 3px; border-bottom: 0; }
  .summary tbody:first-of-type tr.group th { padding-top: 8px; }
  .summary tbody + tbody tr.group th { border-top: 1px solid var(--line-2); }
  .summary tr.group a { color: inherit; text-decoration: none; }
  .summary td:first-child a { color: var(--ink); text-decoration: none; }
  .summary td:first-child a:hover { text-decoration: underline; }
  .data td { white-space: nowrap; font-variant-numeric: tabular-nums; }
  .data tbody tr:nth-child(even) td { background: #fafbfc; }
  .data tr.row-TITLE td { background: var(--tint); font-weight: 600; }
  .data tr.row-NORMAL td { background: #eef5fc; }
  .data tr.row-GREEN td { background: var(--green-bg); }
  .data tr.row-WARNING td { background: var(--amber-bg); }
  .data tr.row-ERRORS td, .data tr.row-FAILED td, .data tr.row-TIMEOUT td, .data tr.row-CRITICAL td { background: var(--red-bg); }

  /* status badges: icon + text, never colour alone */
  .badge { display: inline-flex; align-items: center; gap: 4px; padding: 1px 9px; border-radius: 999px;
           font-size: 12px; font-weight: 600; white-space: nowrap; }
  .badge::before { font-weight: 700; }
  .badge.OK { background: var(--green-bg); color: var(--green); } .badge.OK::before { content: "\2713"; }
  .badge.ERRORS { background: var(--amber-bg); color: var(--amber); } .badge.ERRORS::before { content: "!"; }
  .badge.FAILED, .badge.TIMEOUT { background: var(--red-bg); color: var(--red); }
  .badge.FAILED::before, .badge.TIMEOUT::before { content: "\2715"; }
  .badge.lg { font-size: 15px; padding: 5px 14px; }
  .errs { margin: 0; padding-left: 18px; color: var(--red); font: 12.5px/1.45 var(--mono); }
  span.errs { padding-left: 0; }
  .errbox { background: var(--red-bg); color: var(--red); padding: 12px 14px; border-radius: 8px; font: 13px/1.5 var(--mono); white-space: pre-wrap; }
  .note { color: var(--muted); font-size: 13px; font-style: italic; }

  /* foldable main sections (details.section) and check panels (details.item) */
  summary { cursor: pointer; list-style: none; }
  summary::-webkit-details-marker { display: none; }
  summary::before { content: "\25B8"; color: var(--muted); transition: transform .15s ease; }
  details[open] > summary::before { transform: rotate(90deg); }
  details.section { margin-top: 44px; }
  details.section > summary { display: flex; align-items: center; gap: 10px; padding-bottom: 8px; border-bottom: 1px solid var(--line); }
  details.section[open] > summary { margin-bottom: 12px; }
  details.section > summary h2 { margin: 0; padding: 0; border: 0; }
  details.section > summary:hover h2 { color: #1c5cab; }
  .sec-head { margin: 22px 0 4px; font-size: 14px; color: var(--ink-2); }
  details.item { border: 1px solid var(--line); border-radius: 8px; margin: 8px 0; }
  details.item > summary { display: flex; align-items: center; gap: 10px; padding: 9px 14px; }
  details.item[open] > summary { border-bottom: 1px solid var(--line-2); }
  summary .t { flex: 1; font-weight: 600; }
  summary .secs { color: var(--muted); font-size: 13px; font-variant-numeric: tabular-nums; }
  .panel { padding: 12px 14px 14px; }
  .desc { margin: 0 0 10px; color: var(--ink-2); max-width: 80ch; }
  .panel .errs { margin-bottom: 10px; }
  pre { margin: 0; padding: 12px; background: #f7f8fa; border-radius: 6px; overflow: auto; max-height: 520px;
        font: 12.5px/1.45 var(--mono); white-space: pre; }

  footer { margin: 56px 0 32px; padding-top: 14px; border-top: 1px solid var(--line); color: var(--muted); font-size: 13px; }

  @media (max-width: 960px) {
    .kpis { grid-template-columns: repeat(2, 1fr); }
    .topbar nav { display: none; }
  }
  @media (max-width: 560px) {
    .wrap { padding: 0 16px; }
    .kpis { grid-template-columns: 1fr; }
    .v-head { flex-direction: column; align-items: flex-start; padding: 16px 18px; }
    .v-body { padding: 14px 18px 16px; }
    .verdict h1 { font-size: 30px; }
    .v-sentence { font-size: 17px; }
    .facts { gap: 10px 20px; }
    .facts div { flex: 1 1 40%; }
    #expand-all, #collapse-all { display: none; }
  }
  @media (prefers-reduced-motion: reduce) { summary::before { transition: none; } }
  @media print {
    .topbar { display: none !important; }
    .wrap { max-width: none; padding: 0; }
    .verdict { margin-top: 0; }
    .v-head, .badge, .kpi { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    pre { max-height: none; overflow: visible; white-space: pre-wrap; }
    .kpis, .verdict, tr, summary { break-inside: avoid; }
    h2, h3 { break-after: avoid; }
    a { color: inherit; text-decoration: none; }
    summary::before { display: none; }
  }
</style>
</head>
<body>

<div class="topbar">
  <div class="wrap">
    <div class="name">{{ database_tnsname }} <span class="badge {{ verdict }}">{{ verdict }}</span></div>
    <nav aria-label="Sections">
      {%- if conn_ok %}
      {%- if results | selectattr('section', 'in', table_sections) | list %}<a href="#sec-overview">Overview</a>{% endif %}
      {%- if charts %}<a href="#sec-trends">Trends</a>{% endif %}
      <a href="#sec-summary">Summary</a>
      <a href="#sec-details">Details</a>
      {%- endif %}
    </nav>
    <div class="actions">
      {%- if conn_ok %}
      <button type="button" id="expand-all">Expand all</button>
      <button type="button" id="collapse-all">Collapse all</button>
      {%- endif %}
      <button type="button" id="print-report">Print</button>
    </div>
  </div>
</div>

<main class="wrap">

<section class="verdict v-{{ verdict }}">
  <div class="v-head">
    <h1>{{ database_tnsname }} Health Check</h1>
    <span class="badge lg {{ verdict }}">{{ verdict }}</span>
  </div>
  <div class="v-body">
  <p class="v-sentence">{{ sentence }}</p>
  {%- if bad %}
  <p class="v-att">Needs attention:
    {%- for r in bad %} <a href="#{{ r.script }}">{{ r.short_desc }}</a>{% endfor %}</p>
  {%- endif %}
  <dl class="facts">
    <div><dt>Container</dt><dd>{{ dbi.con_name | default('–') }}</dd></div>
    <div><dt>Database</dt><dd>{{ dbi.db_name | default('–') }}</dd></div>
    <div><dt>Role</dt><dd>{{ dbi.database_role | default('–') }}</dd></div>
    <div><dt>Run</dt><dd class="nowrap">{{ run_ts }}</dd></div>
    {%- if run_id %}<div><dt>Run id</dt><dd>{{ run_id | e }}</dd></div>{% endif %}
    <div><dt>Database user</dt><dd>{{ database_user | default('–') }}</dd></div>
    <div><dt>Executed from</dt><dd>{{ inventory_hostname }}</dd></div>
  </dl>
  </div>
</section>

{% if not conn_ok %}
<h2>Connection failed</h2>
<div class="errbox">{{ conn_error | e }}</div>
{% else %}

{#- ---------- KPI strip ---------- -#}
<div class="kpis">
  {{ tile('Checks passed', counts.OK ~ ' / ' ~ n_total, '',
          ('all scripts ran cleanly' if not bad else bad_txt),
          ('' if not bad else ('crit' if counts.FAILED or counts.TIMEOUT else 'warn')),
          ('' if not bad else 'needs attention')) }}
  {{ tile('Runtime', '%.1f' | format(results | map(attribute='seconds') | map('float') | sum), 's',
          'total SQL*Plus time, ' ~ n_total ~ ' scripts') }}
  {%- if k_load %}
  {%-   set lv = '' if load_pct is none else ('crit' if load_pct >= thr.load_pct[1] else ('warn' if load_pct >= thr.load_pct[0] else '')) %}
  {{ tile('Peak database load', '%.2f' | format(k_load | float), 'sessions',
          ('busiest AWR interval, CPU_COUNT ' ~ k_cpu ~ ' (' ~ ('%.0f' | format(load_pct)) ~ ' %)') if load_pct is not none else 'busiest AWR interval',
          lv, {'crit': 'above CPU_COUNT', 'warn': 'close to CPU_COUNT'}[lv] | default('')) }}
  {%- else %}
  {{ tile('Peak database load', '–', '', 'no AWR data') }}
  {%- endif %}
  {%- if k_host %}
  {%-   set lv = 'crit' if k_host | float >= thr.host_cpu[1] else ('warn' if k_host | float >= thr.host_cpu[0] else '') %}
  {{ tile('Peak host CPU', '%.0f' | format(k_host | float), '%', 'busiest node and AWR interval',
          lv, {'crit': 'host saturated', 'warn': 'host busy'}[lv] | default('')) }}
  {%- else %}
  {{ tile('Peak host CPU', '–', '', 'no AWR data') }}
  {%- endif %}
  {%- if k_lfs %}
  {%-   set lv = 'crit' if k_lfs | float >= thr.commit_ms[1] else ('warn' if k_lfs | float >= thr.commit_ms[0] else '') %}
  {{ tile('Peak commit time', '%.1f' | format(k_lfs | float), 'ms', 'log file sync, busiest AWR interval',
          lv, {'crit': 'slow commits', 'warn': 'commits slowing'}[lv] | default('')) }}
  {%- else %}
  {{ tile('Peak commit time', '–', '', 'no AWR data') }}
  {%- endif %}
</div>

{#- ---------- overview tables (STATUS column, if present and not first, colours the row) ---------- -#}
{%- set ov = results | selectattr('section', 'in', table_sections) | list %}
{%- if ov %}
<details class="section" id="sec-overview" open>
<summary><h2>Overview</h2></summary>
{%- for r in ov %}
{%-   set lines = (r.output | default('')).splitlines() %}
<h3>{{ r.short_desc }}</h3>
{%-   if lines | length > 1 and '|' in lines[1] %}
{%-     set hdr = lines[1].split('|') | map('trim') | list %}
{%-     set si = namespace(idx=0) %}
{%-     for c in hdr %}{% if c == 'STATUS' %}{% set si.idx = loop.index0 %}{% endif %}{% endfor %}
<div class="tablewrap">
<table class="data">
  <thead><tr>{% for c in hdr %}<th>{{ c | e }}</th>{% endfor %}</tr></thead>
  <tbody>
  {%- for line in lines[2:] if '|' in line and not line.startswith('---') %}
  {%-   set cols = line.split('|') | map('trim') | list %}
    <tr{% if si.idx > 0 %} class="row-{{ cols[si.idx] | default('') | e }}"{% endif %}>
    {%- for c in cols %}
      {%- if si.idx > 0 and loop.index0 == si.idx and c in ['OK', 'ERRORS', 'FAILED', 'TIMEOUT'] %}<td><span class="badge {{ c }}">{{ c }}</span></td>
      {%- else %}<td>{{ c | e }}</td>{% endif %}
    {%- endfor %}
    </tr>
  {%- endfor %}
  </tbody>
</table>
</div>
{%-   else %}
<p class="note">No table in the output (status {{ r.status }}), see <a href="#{{ r.script }}">its details</a>.</p>
{%-   endif %}
{%- endfor %}
</details>
{%- endif %}

{#- ---------- trends: section, chart CSS and Google Charts code live in trends.html.j2 ---------- -#}
{% include 'trends.html.j2' %}

{#- ---------- summary ---------- -#}
<details class="section" id="sec-summary" open>
<summary><h2>Summary of health check
  {%- for s, n in counts.items() if n %} <span class="badge {{ s }}">{{ n }} {{ s }}</span>{% endfor %}</h2></summary>
<div class="tablewrap">
<table class="summary">
  <thead><tr><th>Check</th><th class="c">Status</th><th class="r">Time (s)</th><th>Errors</th></tr></thead>
  {%- for s in sec.names %}
  <tbody>
    <tr class="group"><th colspan="4"><a href="#{{ slug(s) }}">{{ human(s) }}</a></th></tr>
    {%- for r in results if r.section == s %}
    <tr>
      <td><a href="#{{ r.script }}">{{ r.short_desc }}</a></td>
      <td class="c"><span class="badge {{ r.status }}">{{ r.status }}</span></td>
      <td class="r">{{ r.seconds }}</td>
      <td>{% if r.status == 'TIMEOUT' %}<span class="errs">killed after {{ script_timeout | default('?') }} s</span>
          {%- elif r.status == 'FAILED' %}<span class="errs">sqlplus exited with code {{ r.rc }}</span>{% if r.errors %}<ul class="errs">{% for e in r.errors %}<li>{{ e | e }}</li>{% endfor %}</ul>{% endif %}
          {%- elif r.errors %}<ul class="errs">{% for e in r.errors %}<li>{{ e | e }}</li>{% endfor %}</ul>{% endif %}</td>
    </tr>
    {%- endfor %}
  </tbody>
  {%- endfor %}
</table>
</div>
</details>

{#- ---------- detail panels ---------- -#}
<details class="section" id="sec-details" open>
<summary><h2>Details</h2></summary>
{%- for s in sec.names %}
{%-   set rs = results | selectattr('section', 'equalto', s) | list %}
<h3 class="sec-head" id="{{ slug(s) }}">{{ human(s) }}</h3>
{%-   for r in rs %}
<details class="item" id="{{ r.script }}"{% if r.status != 'OK' %} open{% endif %}>
  <summary><span class="badge {{ r.status }}">{{ r.status }}</span><span class="t">{{ r.short_desc }}</span><span class="secs">{{ r.seconds }} s</span></summary>
  <div class="panel">
    {%- if descs[r.script] | default('') | trim %}
    <p class="desc">{{ descs[r.script] }}</p>
    {%- endif %}
    {%- if r.errors %}<ul class="errs">{% for e in r.errors %}<li>{{ e | e }}</li>{% endfor %}</ul>{% endif %}
    {%- if (r.output | length) > (html_max_log_kb | default(512) | int) * 1024 %}
    <p class="note">Output is {{ ((r.output | length) / 1024) | round | int }} KB, too large to embed. Open <a href="{{ r.log }}">{{ r.log }}</a>.</p>
    {%- elif not r.output | trim %}
    <p class="note">No output.</p>
    {%- else %}
    <pre>{{ r.output | e }}</pre>
    {%- endif %}
  </div>
</details>
{%-   endfor %}
{%- endfor %}
</details>

{% endif %}

{%- set build_id = lookup('env', 'BUILD_BUILDID') %}
<footer>
  Generated by ansible-role-db-healthcheck on {{ inventory_hostname }}. Run time is Europe/Amsterdam; chart times are database server time.
  {%- if build_id %}
  Pipeline run <a href="{{ lookup('env', 'SYSTEM_COLLECTIONURI') }}{{ lookup('env', 'SYSTEM_TEAMPROJECT') | urlencode }}/_build/results?buildId={{ build_id }}">{{ lookup('env', 'BUILD_DEFINITIONNAME') }} {{ lookup('env', 'BUILD_BUILDNUMBER') }}</a>.
  {%- endif %}
</footer>
</main>

<script>
(function () {
  var all = function () { return Array.prototype.slice.call(document.querySelectorAll('details')); };
  var on = function (id, fn) { var b = document.getElementById(id); if (b) b.addEventListener('click', fn); };
  on('expand-all', function () { all().forEach(function (d) { d.open = true; }); });
  on('collapse-all', function () { all().forEach(function (d) { d.open = false; }); });
  on('print-report', function () { window.print(); });
  var saved = null;
  window.addEventListener('beforeprint', function () { saved = all().map(function (d) { return d.open; }); all().forEach(function (d) { d.open = true; }); });
  window.addEventListener('afterprint', function () { if (saved) { all().forEach(function (d, i) { d.open = saved[i]; }); } saved = null; });
  /* an in-page link opens its target and every folded section around it */
  var reveal = function (id) { for (var el = document.getElementById(id); el; el = el.parentElement) { if (el.tagName === 'DETAILS') el.open = true; } };
  document.addEventListener('click', function (e) {
    var a = e.target.closest ? e.target.closest('a[href^="#"]') : null;
    if (a) reveal(decodeURIComponent(a.getAttribute('href').slice(1)));
  });
  if (location.hash) reveal(decodeURIComponent(location.hash.slice(1)));
})();
</script>
</body>
</html>
