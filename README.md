{#- Trends: one Google Chart per script in section 'Trends'.
    Included from report.html.j2 right after the Summary table; uses its context (results, awr_days).
    Script output contract, all lines '|'-separated:
      CHART|<line or stacked>|<title>|<v-axis title>
      header line, first column = snapshot time
      data lines, time as YYYY-MM-DDTHH24:MI:SS; empty or '-' = no value (gap)
    Anything before the CHART line and any line without '|' is ignored. -#}
{%- set trends = results | selectattr('section', 'equalto', 'Trends') | list %}
{%- if trends %}
<style>
  .hc-card { border: 1px solid var(--line, #dde1e6); border-radius: 8px; background: #fff;
             box-shadow: 0 1px 2px rgba(16, 24, 40, .06); padding: .8rem 1rem .3rem; margin: 1rem 0; }
  .hc-card h3 { text-align: center; font-size: .95rem; margin: 0; }
  .hc-chart { min-height: 340px; }
  .hc-center { text-align: center; }
</style>
<h2>Trends &ndash; last {{ awr_days }} days</h2>
{%- for r in trends %}
{%-   set ns = namespace(data=[]) %}
{%-   for l in (r.output | default('')).splitlines() | map('trim') %}
{%-     if (ns.data or l.startswith('CHART|')) and '|' in l %}{% set ns.data = ns.data + [l] %}{% endif %}
{%-   endfor %}
{%-   if ns.data | length > 2 %}
{%-     set meta = ns.data[0].split('|') %}
{%-     set spec = {
          'type':   meta[1] | default('line'),
          'title':  meta[2] | default(r.short_desc),
          'vtitle': meta[3] | default(''),
          'cols':   ns.data[1].split('|'),
          'rows':   ns.data[2:] | map('split', '|') | list } %}
<div class="hc-card"><h3>{{ spec.title | e }}</h3><div class="hc-chart" data-spec="{{ spec | to_json | e }}"></div></div>
{%-   else %}
<p class="note">{{ r.short_desc | e }}: no chart data &ndash; status {{ r.status }}, see the script's panel below.</p>
{%-   endif %}
{%- endfor %}
<p class="note hc-center">Charts: drag to zoom, right-click to reset.</p>
<script src="https://www.gstatic.com/charts/loader.js"></script>
<script>
(function () {
  var nodes = document.querySelectorAll('div.hc-chart');
  if (!window.google || !google.charts) {
    for (var k = 0; k < nodes.length; k++) {
      nodes[k].style.minHeight = '0';
      nodes[k].innerHTML = '<p class="note">Chart not drawn: www.gstatic.com/charts/loader.js could not be loaded.</p>';
    }
    return;
  }
  google.charts.load('current', {packages: ['corechart']});
  google.charts.setOnLoadCallback(function () {
    for (var n = 0; n < nodes.length; n++) {
      var el = nodes[n];
      var s = JSON.parse(el.getAttribute('data-spec'));
      var dt = new google.visualization.DataTable();
      var series = {};
      dt.addColumn('datetime', s.cols[0]);
      for (var c = 1; c < s.cols.length; c++) {
        dt.addColumn('number', s.cols[c]);
        if (/cpu_count/i.test(s.cols[c])) { series[c - 1] = {lineDashStyle: [6, 4], color: '#b42318'}; }
      }
      for (var i = 0; i < s.rows.length; i++) {
        var r = s.rows[i];
        var row = [new Date(r[0])];
        for (var j = 1; j < s.cols.length; j++) {
          var v = r[j];
          row.push(v === undefined || v === '' || v === '-' ? null : Number(v));
        }
        dt.addRow(row);
      }
      var opts = {
        titlePosition: 'none',
        height: 340,
        isStacked: s.type === 'stacked',
        focusTarget: 'category',
        series: series,
        legend: {position: 'top', alignment: 'center', maxLines: 3, textStyle: {fontSize: 11}},
        chartArea: {left: 70, right: 70, top: s.cols.length > 6 ? 64 : 36, bottom: 70},
        hAxis: {format: 'MMM d HH:mm', slantedText: true, textStyle: {fontSize: 10}},
        vAxis: {title: s.vtitle, viewWindow: {min: 0}},
        explorer: {actions: ['dragToZoom', 'rightClickToReset'], axis: 'horizontal', maxZoomIn: 0.05}
      };
      var Chart = s.type === 'stacked' ? google.visualization.AreaChart : google.visualization.LineChart;
      new Chart(el).draw(dt, opts);
    }
  });
})();
</script>
{%- endif %}
