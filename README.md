{#- Health check report for one database and one run. -#}
{%- set counts = {} -%}
{%- for s in ['OK', 'ERRORS', 'FAILED', 'TIMEOUT'] -%}
{%-   set _ = counts.update({s: results | selectattr('status', 'equalto', s) | list | length}) -%}
{%- endfor -%}
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{ pdb_folder }} health check {{ run_ts }}</title>
<style>
  :root { --red:#b42318; --red-bg:#fde8e6; --amber:#8a5a00; --amber-bg:#fff4d6;
          --green:#1e7a3d; --green-bg:#e3f4e8; --line:#dde1e6; --muted:#5b6573; }
  body  { font-family: -apple-system, "Segoe UI", Roboto, sans-serif; margin: 2rem auto; max-width: 1200px;
          padding: 0 1rem; color: #1d2430; }
  h1    { font-size: 1.4rem; margin: 0 0 .3rem; }
  h2    { font-size: 1.05rem; margin: 2rem 0 .6rem; padding-bottom: .25rem; border-bottom: 2px solid #c74634; }
  .meta { color: var(--muted); font-size: .85rem; line-height: 1.6; }
  code  { background: #f2f4f7; padding: 0 .3rem; border-radius: 3px; }
  table { border-collapse: collapse; font-size: .85rem; width: 100%; }
  th, td { border: 1px solid var(--line); padding: .35rem .7rem; text-align: left; vertical-align: top; }
  th    { background: #f4f5f7; }
  td.num, td:nth-child(2) { white-space: nowrap; }
  td.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .badge { display: inline-block; padding: .05rem .5rem; border-radius: 999px; font-size: .75rem; font-weight: 600; }
  .OK { background: var(--green-bg); color: var(--green); }
  .ERRORS { background: var(--amber-bg); color: var(--amber); }
  .FAILED, .TIMEOUT { background: var(--red-bg); color: var(--red); }
  .errs { font-family: ui-monospace, Consolas, monospace; font-size: .78rem; color: var(--red); margin: 0; padding-left: 1rem; }
  details { border: 1px solid var(--line); border-radius: 6px; margin: .6rem 0; }
  summary { cursor: pointer; padding: .5rem .8rem; background: #f8f9fa; font-weight: 600; }
  pre   { margin: 0; padding: .8rem; overflow-x: auto; font-size: .78rem; line-height: 1.35;
          font-family: ui-monospace, Consolas, monospace; white-space: pre; }
  .errbox { background: var(--red-bg); color: var(--red); padding: .7rem .9rem; border-radius: 6px;
            font-family: ui-monospace, Consolas, monospace; font-size: .85rem; }
  .note { color: var(--muted); font-size: .8rem; font-style: italic; padding: .5rem .8rem; }
</style>
</head>
<body>
<h1>Health check: {{ pdb_folder }}</h1>
<div class="meta">
  Target <code>{{ inventory_hostname }}</code> · <code>{{ dsn | regex_replace("\s+", "") | e }}</code> as {{ ora_user }}
  {%- if db_info %} · DB {{ db_info.db_name }} / container {{ db_info.con_name }} · {{ db_info.database_role }}{% endif %}<br>
  Run {{ run_ts }}{% if run_id %} · id {{ run_id | e }}{% endif %} · scripts from <code>{{ scripts_dir }}</code>
  {%- if read_only_session %} · read-only sessions{% endif %}
</div>

{% if not conn_ok %}
<h2>Connection failed – no scripts were run</h2>
<div class="errbox">{{ conn_error | e }}</div>
{% else %}
<h2>Summary
  {%- for s, n in counts.items() if n %} <span class="badge {{ s }}">{{ n }} {{ s }}</span>{% endfor %}</h2>
<table>
  <thead><tr><th>Script</th><th>Status</th><th>Time (s)</th><th>Errors</th><th>Log</th></tr></thead>
  <tbody>
{% for r in results %}
    <tr>
      <td><a href="#{{ r.log }}">{{ r.script }}</a></td>
      <td><span class="badge {{ r.status }}">{{ r.status }}</span></td>
      <td class="num">{{ r.seconds }}</td>
      <td>{% if r.status == 'TIMEOUT' %}<span class="errs">killed after {{ script_timeout }} s</span>
          {%- elif r.status == 'FAILED' %}<span class="errs">sqlplus exited with code {{ r.rc }}</span>{% if r.errors %}<ul class="errs">{% for e in r.errors %}<li>{{ e | e }}</li>{% endfor %}</ul>{% endif %}
          {%- elif r.errors %}<ul class="errs">{% for e in r.errors %}<li>{{ e | e }}</li>{% endfor %}</ul>{% endif %}</td>
      <td><a href="{{ r.log }}">{{ r.log }}</a></td>
    </tr>
{% endfor %}
  </tbody>
</table>

<h2>Output</h2>
{% for r in results %}
<details id="{{ r.log }}"{% if r.status != 'OK' %} open{% endif %}>
  <summary><span class="badge {{ r.status }}">{{ r.status }}</span> {{ r.script }}</summary>
{%   if (r.output | length) > (html_max_log_kb | int) * 1024 %}
  <p class="note">Output is {{ ((r.output | length) / 1024) | round | int }} KB – too large to embed;
     open <a href="{{ r.log }}">{{ r.log }}</a>.</p>
{%   elif not r.output | trim %}
  <p class="note">No output.</p>
{%   else %}
  <pre>{{ r.output | e }}</pre>
{%   endif %}
</details>
{% endfor %}
{% endif %}
</body>
</html>
