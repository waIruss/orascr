{#- Trends section, included from report.html.j2.
    Works with both main templates:
      - new report.html.j2: uses `charts` it parsed at the top, renders a foldable section (styled by the main template)
      - any other report.html.j2 (e.g. the original): parses the Trends results itself, renders a plain <h2> section
    Each chart: {script, status, short_desc, ok, type: line|stacked, title, vtitle, cols, rows}.
    Script output contract, '|'-separated: CHART|<line|stacked>|<title>|<v-axis title>, header, data rows. -#}
{%- set tr_standalone = charts is not defined %}
{%- if tr_standalone %}
{%-   set tr = namespace(list=[]) %}
{%-   for r in results | default([]) if r.section == 'Trends' %}
{%-     set ln = namespace(data=[]) %}
{%-     for l in (r.output | default('')).splitlines() | map('trim') %}
{%-       if (ln.data or l.startswith('CHART|')) and '|' in l %}{% set ln.data = ln.data + [l] %}{% endif %}
{%-     endfor %}
{%-     if ln.data | length > 2 %}
{%-       set meta = ln.data[0].split('|') %}
{%-       set tr.list = tr.list + [{'script': r.script, 'status': r.status, 'short_desc': r.short_desc, 'ok': true,
                                   'type': meta[1] | default('line'), 'title': meta[2] | default(r.short_desc),
                                   'vtitle': meta[3] | default(''), 'cols': ln.data[1].split('|'),
                                   'rows': ln.data[2:] | map('split', '|') | list}] %}
{%-     else %}
{%-       set tr.list = tr.list + [{'script': r.script, 'status': r.status, 'short_desc': r.short_desc, 'ok': false}] %}
{%-     endif %}
{%-   endfor %}
{%-   set tr_charts = tr.list %}
{%- else %}
{%-   set tr_charts = charts %}
{%- endif %}
{%- if tr_charts %}
<style>
  .charts { display: grid; grid-template-columns: 1fr 1fr; grid-auto-flow: row dense; gap: 16px; }
  .chart { border: 1px solid var(--line); border-radius: 8px; padding: 14px 10px 4px; min-width: 0; }
  .chart.wide { grid-column: 1 / -1; }
  .chart h3 { margin: 0; text-align: center; font-size: 15px; }
  .chart .sub { margin: 2px 0 0; text-align: center; font-size: 13px; color: var(--muted); }
  .chart .sub:empty { display: none; }
  .chart .plot { height: 320px; }
  .chart > .note { text-align: center; padding: 40px 0; }
  .hint { text-align: center; }
  .tr-count { margin-left: 8px; font-size: .8em; font-weight: 400; color: var(--muted); }
  @media (max-width: 960px) { .charts { grid-template-columns: 1fr; } }
  @media print { .hint { display: none; } .chart { break-inside: avoid; } }
</style>
{%- if tr_standalone %}
<h2 id="sec-trends">Trends<span class="tr-count">last {{ awr_days | default(7) }} days, database server time</span></h2>
{%- else %}
<details class="section" id="sec-trends" open>
<summary><h2>Trends<span class="count">last {{ awr_days | default(7) }} days, database server time</span></h2></summary>
{%- endif %}
<div class="charts">
{%- for c in tr_charts %}
{%-   if c.ok %}
  <div class="chart{{ ' wide' if c.type == 'stacked' }}" data-spec="{{ c | to_json | e }}">
    <h3>{{ c.title | e }}</h3><p class="sub"></p><div class="plot"></div>
  </div>
{%-   else %}
  <div class="chart">
    <h3>{{ c.short_desc | e }}</h3>
    <p class="note">No chart data (status {{ c.status }}), see <a href="#{{ c.script }}">its details</a>.</p>
  </div>
{%-   endif %}
{%- endfor %}
</div>
<p class="note hint">Hover a chart for values. Drag to zoom, right-click to reset.</p>
{%- if not tr_standalone %}
</details>
{%- endif %}
{%- if tr_charts | selectattr('ok') | list %}
<script src="https://www.gstatic.com/charts/loader.js"></script>
<script>
(function () {
  /* Series colours: fixed categorical order; wait classes use the Enterprise Manager convention. */
  var PALETTE = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#6250d6', '#e34948'];
  var WAIT = {'CPU': '#00cc00', 'Scheduler': '#ccffcc', 'User I/O': '#004ae7', 'System I/O': '#0094e7',
              'Concurrency': '#8b1a00', 'Application': '#c02800', 'Commit': '#e46800', 'Configuration': '#5c440b',
              'Administrative': '#717354', 'Network': '#9f9371', 'Queueing': '#c2b79b', 'Cluster': '#c9c2af', 'Other': '#f06eaa'};
  var WAIT_ORDER = Object.keys(WAIT);
  var REF = /cpu_count/i, MUTED = '#5b6573', GRID = '#eceae4', AXIS = '#c3c2b7';
  var cards = Array.prototype.slice.call(document.querySelectorAll('.chart[data-spec]'));
  if (!window.google || !google.charts) {
    cards.forEach(function (c) { c.querySelector('.plot').outerHTML = '<p class="note">Chart not drawn: www.gstatic.com/charts/loader.js could not be loaded.</p>'; });
    return;
  }
  var num = function (v) { return (v === undefined || v === '' || v === '-') ? null : Number(v); };
  var font = getComputedStyle(document.body).fontFamily;

  function prepare(card) {
    var s = JSON.parse(card.getAttribute('data-spec'));
    var plot = card.querySelector('.plot'), sub = card.querySelector('.sub');
    var rows = s.rows.map(function (r) { return r.map(function (v, i) { return i === 0 ? new Date(v) : num(v); }); });
    var colMax = function (i) { return rows.reduce(function (m, r) { return r[i] !== null && r[i] > m ? r[i] : m; }, 0); };
    var keep = [];
    for (var i = 1; i < s.cols.length; i++) keep.push(i);
    var stacked = s.type === 'stacked';
    if (stacked) {                                   /* drop classes with no time, stack in EM order */
      keep = keep.filter(function (i) { return colMax(i) > 0; });
      var rank = function (i) { var k = WAIT_ORDER.indexOf(s.cols[i]); return k < 0 ? 99 : k; };
      keep.sort(function (a, b) { return rank(a) - rank(b); });
    }
    var ref = keep.filter(function (i) { return REF.test(s.cols[i]); })[0];
    if (ref !== undefined) {                         /* reference line only when it does not flatten the data */
      var refVal = rows.length ? rows[rows.length - 1][ref] : null;
      var peak = Math.max.apply(null, [0].concat(keep.filter(function (i) { return i !== ref; }).map(colMax)));
      if (refVal && peak < 0.25 * refVal) {
        keep = keep.filter(function (i) { return i !== ref; });
        sub.textContent = 'CPU_COUNT ' + refVal + ' not drawn: the peak of ' + peak.toFixed(2) + ' is below a quarter of it.';
      } else if (refVal) {
        sub.textContent = 'Dashed line: CPU_COUNT ' + refVal;
      }
    }
    if (!keep.length) {
      plot.outerHTML = '<p class="note">No non-idle activity in this period.</p>';
      return null;
    }
    var dt = new google.visualization.DataTable();
    dt.addColumn('datetime', s.cols[0]);
    keep.forEach(function (i) { dt.addColumn('number', s.cols[i]); });
    dt.addRows(rows.map(function (r) { return [r[0]].concat(keep.map(function (i) { return r[i]; })); }));
    var colors = [], series = {}, slot = 0;
    keep.forEach(function (i, k) {
      if (i === ref) { colors.push(MUTED); series[k] = {lineDashStyle: [6, 4], lineWidth: 1.5}; }
      else if (stacked && WAIT[s.cols[i]]) { colors.push(WAIT[s.cols[i]]); }
      else { colors.push(PALETTE[slot++ % PALETTE.length]); }
    });
    var opts = {
      height: 320, fontName: font, backgroundColor: 'transparent', titlePosition: 'none',
      isStacked: stacked, areaOpacity: stacked ? 0.9 : 0, lineWidth: stacked ? 0 : 2,
      colors: colors, series: series, focusTarget: 'category',
      crosshair: {trigger: 'focus', orientation: 'vertical', color: AXIS},
      legend: {position: 'top', alignment: 'center', maxLines: 3, textStyle: {color: '#3b4452', fontSize: 12}},
      chartArea: {left: 64, right: 64, top: keep.length > 5 ? 58 : 34, bottom: 40},
      hAxis: {textStyle: {color: MUTED, fontSize: 11}, baselineColor: AXIS, minorGridlines: {count: 0},
              gridlines: {color: GRID, units: {days: {format: ['EEE d MMM']}, hours: {format: ['HH:mm']}}}},
      vAxis: {title: s.vtitle, titleTextStyle: {color: MUTED, fontSize: 12, italic: false},
              textStyle: {color: MUTED, fontSize: 11}, gridlines: {color: GRID}, minorGridlines: {count: 0},
              baselineColor: AXIS, viewWindow: {min: 0}},
      explorer: {actions: ['dragToZoom', 'rightClickToReset'], axis: 'horizontal', maxZoomIn: 0.05}
    };
    var chart = new (stacked ? google.visualization.AreaChart : google.visualization.LineChart)(plot);
    return function () { if (plot.offsetWidth) chart.draw(dt, opts); };   /* skip while the section is folded */
  }

  google.charts.load('current', {packages: ['corechart']});
  google.charts.setOnLoadCallback(function () {
    var draws = cards.map(prepare).filter(Boolean);
    var redraw = function () { draws.forEach(function (d) { d(); }); };
    redraw();
    var sec = document.getElementById('sec-trends'), t;
    if (sec) sec.addEventListener('toggle', function () { if (sec.open) redraw(); });
    window.addEventListener('resize', function () { clearTimeout(t); t = setTimeout(redraw, 200); });
  });
})();
</script>
{%- endif %}
{%- endif %}
