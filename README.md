---
# Oracle health check: run every SQL*Plus script in scripts_dir, unchanged, against
# each database in the inventory, and store the output on this server:
#
#   <output_base>/pdbs/<PDB>/<YYYY-MM-DD_HHMMSS>/
#       01_sessions.log, 02_tablespaces.log, ...   raw SQL*Plus output, one per script
#       report.html                                 summary + every log, in one page
#       summary.json                                machine-readable status per script
#   <output_base>/pdbs/<PDB>/latest -> <newest run>
#
# Locally:   ./run.sh                     (see README)
# Pipeline:  ansible-playbook healthcheck.yml -e ora_password=... -e run_id=...
#
# Each script gets its own sqlplus session: an error or hang affects one script only,
# and `timeout` kills a stuck script without touching the rest.
# Every task that sees the password is no_log; later tasks only read sanitized facts.

- name: Oracle health check
  hosts: oracle_db
  gather_facts: false

  vars:
    # Play-internal values only. Tunables: group_vars/oracle_db/main.yml;
    # sqlplus_bin, sqlplus_env, connect_id: group_vars/oracle_db/derived.yml.
    marker: "###HEALTHCHECK_OUTPUT_STARTS###"
    file_mode: "{{ '0640' if output_group else '0600' }}"
    dir_mode: "{{ '2750' if output_group else '0700' }}"
    safe_run_id: "{{ run_id | regex_replace('[^A-Za-z0-9._-]', '') }}"

  tasks:
    # ------------------------------------------------------------------ inputs
    - name: Freeze run timestamp (same folder name for every database in this run)
      run_once: true
      ansible.builtin.set_fact:
        run_ts: "{{ run_ts | default(now(fmt=run_ts_format)) }}"

    - name: Find scripts
      run_once: true
      ansible.builtin.find:
        paths: "{{ scripts_dir }}"
        patterns: "{{ scripts_patterns }}"
        excludes: "{{ scripts_excludes }}"
        file_type: file
      register: found

    - name: Check there is something to run
      run_once: true
      ansible.builtin.assert:
        that: found.files | length > 0
        fail_msg: "no scripts matching {{ scripts_patterns }} in {{ scripts_dir }}"
        quiet: true

    - name: Fix script order (file name)
      run_once: true
      ansible.builtin.set_fact:
        scripts: "{{ found.files | map(attribute='path') | sort }}"

    - name: Check connection settings
      ansible.builtin.assert:
        that:
          - dsn is defined and dsn | length > 0
          - ora_password is defined
        fail_msg: >-
          {{ inventory_hostname }}: needs dsn in inventory.yml and a password
          (credentials file entry or -e ora_password)
        quiet: true

    # -------------------------------------------------------------- connection
    - name: Test connection
      ansible.builtin.command:
        cmd: "timeout {{ connect_timeout }} {{ sqlplus_bin }} -S -L /nolog"
        stdin: |
          WHENEVER SQLERROR EXIT FAILURE
          SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 400 TRIMOUT ON
          CONNECT {{ ora_user }}/"{{ ora_password }}"@{{ connect_id }}
          SELECT 'CONNECT_OK|' || sys_context('USERENV','CON_NAME')
                 || '|' || sys_context('USERENV','DB_NAME')
                 || '|' || sys_context('USERENV','DATABASE_ROLE') FROM dual;
          EXIT
      environment: "{{ sqlplus_env }}"
      register: conn
      changed_when: false
      failed_when: false
      no_log: true

    - name: Record connection result
      ansible.builtin.set_fact:
        conn_ok: "{{ ok_line | length > 0 }}"
        db_info: >-
          {{ dict(['con_name', 'db_name', 'database_role'] | zip(ok_line.split('|')[1:]))
             if ok_line else {} }}
        conn_error: >-
          {{ '' if ok_line else
             (conn.stdout_lines | select('match', '(ORA|SP2|TNS)-[0-9]+') | first
              | default('timed out after ' ~ connect_timeout ~ ' s' if conn.rc == 124
                        else 'sqlplus rc=' ~ conn.rc ~ ' ' ~ (conn.stderr | trim))) }}
      vars:
        ok_line: "{{ conn.stdout_lines | select('match', 'CONNECT_OK[|]') | first | default('') }}"

    - name: Prepare run folder
      ansible.builtin.set_fact:
        pdb_folder: "{{ (pdb_name | default(db_info.con_name | default(inventory_hostname | upper)))
                        | regex_replace('[^A-Za-z0-9_.-]', '_') }}"

    - name: Create run folder
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        mode: "{{ dir_mode }}"
        group: "{{ output_group or omit }}"
      loop:
        - "{{ output_base }}/pdbs"
        - "{{ output_base }}/pdbs/{{ pdb_folder }}"
        - "{{ output_base }}/pdbs/{{ pdb_folder }}/{{ run_ts }}"

    - name: Remember run folder
      ansible.builtin.set_fact:
        run_dir: "{{ output_base }}/pdbs/{{ pdb_folder }}/{{ run_ts }}"

    # ----------------------------------------------------------------- scripts
    # Scripts run unchanged: no SET/WHENEVER imposed on them (SQL*Plus defaults apply).
    # cwd = run folder, so a SPOOL inside a script lands next to the logs;
    # @@ includes still resolve relative to the script's own directory.
    # The preamble's own output is cut off at the marker.
    - name: Run scripts
      ansible.builtin.command:
        cmd: "timeout {{ script_timeout }} {{ sqlplus_bin }} -S -L /nolog"
        chdir: "{{ run_dir }}"
        stdin: |
          SET FEEDBACK OFF
          CONNECT {{ ora_user }}/"{{ ora_password }}"@{{ connect_id }}
          {% if read_only_session %}SET TRANSACTION READ ONLY;{% endif %}

          EXEC DBMS_APPLICATION_INFO.SET_MODULE('ansible-healthcheck', '{{ (item | basename)[:32] }}')
          EXEC DBMS_SESSION.SET_IDENTIFIER('{{ safe_run_id }}')
          SET FEEDBACK 6
          PROMPT {{ marker }}
          @"{{ item }}"
          EXIT
      environment: "{{ sqlplus_env }}"
      loop: "{{ scripts }}"
      loop_control: { label: "{{ item | basename }}" }
      register: runs
      when: conn_ok
      changed_when: false
      failed_when: false
      no_log: true

    # Errors are recognised the way SQL*Plus reports them: an ORA- line right after
    # "ERROR..." or any SP2- line. ORA- text that is *data* (e.g. an alert log check
    # listing ORA-00600) does not count.
    - name: Classify script results
      ansible.builtin.set_fact:
        results: >-
          {%- set out = [] -%}
          {%- for r in runs.results | default([]) if conn_ok -%}
          {%-   set raw = r.stdout | default('') -%}
          {%-   set log = (raw.split(marker, 1)[1] | regex_replace('^\n', '')) if marker in raw else raw -%}
          {%-   set lines = log.splitlines() -%}
          {%-   set errs = [] -%}
          {%-   for l in lines -%}
          {%-     if l is match('SP2-[0-9]+') or (l is match('ORA-[0-9]+') and loop.index0 > 0
                                                  and lines[loop.index0 - 1] is match('ERROR')) -%}
          {%-       set _ = errs.append(l | trim) -%}
          {%-     endif -%}
          {%-   endfor -%}
          {%-   set status = 'TIMEOUT' if r.rc == 124 else ('FAILED' if r.rc != 0 else ('ERRORS' if errs else 'OK')) -%}
          {%-   set name = r.item | basename -%}
          {%-   set _ = out.append({
                  'script': name,
                  'log': name | regex_replace('\.sql$', '') ~ '.log',
                  'status': status,
                  'rc': r.rc,
                  'start': r.start | default(''),
                  'seconds': ((r.end | to_datetime('%Y-%m-%d %H:%M:%S.%f')) - (r.start | to_datetime('%Y-%m-%d %H:%M:%S.%f'))).total_seconds() | round(1) if r.end is defined else 0,
                  'errors': errs[:10],
                  'output': log ~ (('\n' ~ r.stderr) if r.stderr | default('') else '')}) -%}
          {%- endfor -%}
          {{ out }}

    # ------------------------------------------------------------------ output
    - name: Write one log per script
      ansible.builtin.copy:
        content: "{{ item.output ~ '\n' }}"     # command output loses its final newline
        dest: "{{ run_dir }}/{{ item.log }}"
        mode: "{{ file_mode }}"
        group: "{{ output_group or omit }}"
      loop: "{{ results }}"
      loop_control: { label: "{{ item.log }}" }

    - name: Write summary.json
      ansible.builtin.copy:
        content: >-
          {{ {
               'target': inventory_hostname, 'dsn': dsn | regex_replace('\s+', ''), 'user': ora_user,
               'pdb_folder': pdb_folder, 'db': db_info, 'run_ts': run_ts, 'run_id': run_id,
               'connected': conn_ok, 'connection_error': conn_error,
               'scripts': results | map('dict2items') | map('rejectattr', 'key', 'equalto', 'output')
                                  | map('items2dict') | list
             } | to_nice_json }}
        dest: "{{ run_dir }}/summary.json"
        mode: "{{ file_mode }}"
        group: "{{ output_group or omit }}"

    - name: Write report.html
      ansible.builtin.template:
        src: report.html.j2
        dest: "{{ run_dir }}/report.html"
        mode: "{{ file_mode }}"
        group: "{{ output_group or omit }}"

    # Files a script SPOOLs itself are created with the user's umask; align them.
    - name: Find files created by scripts
      ansible.builtin.find:
        paths: "{{ run_dir }}"
      register: run_files

    - name: Apply output permissions to everything in the run folder
      ansible.builtin.file:
        path: "{{ item.path }}"
        mode: "{{ file_mode }}"
        group: "{{ output_group or omit }}"
      loop: "{{ run_files.files }}"
      loop_control: { label: "{{ item.path | basename }}" }

    - name: Point latest at this run
      ansible.builtin.file:
        src: "{{ run_ts }}"
        dest: "{{ output_base }}/pdbs/{{ pdb_folder }}/latest"
        state: link
        force: true

    - name: Find old runs
      ansible.builtin.find:
        paths: "{{ output_base }}/pdbs/{{ pdb_folder }}"
        file_type: directory
        age: "{{ keep_days }}d"
      register: old_runs
      when: keep_days | int > 0

    - name: Delete old runs
      ansible.builtin.file:
        path: "{{ item.path }}"
        state: absent
      loop: "{{ old_runs.files | default([]) | rejectattr('path', 'equalto', run_dir) | list }}"
      loop_control: { label: "{{ item.path | basename }}" }
      when: keep_days | int > 0

    # ----------------------------------------------------------------- verdict
    - name: Result
      ansible.builtin.debug:
        msg: >-
          {{ [run_dir ~ '/report.html']
             + ([('CONNECT FAILED: ' ~ conn_error)] if not conn_ok else
                results | map(attribute='status') | zip(results | map(attribute='script'))
                        | map('join', '  ') | list) }}

    - name: Fail if the connection failed or a script ended in {{ fail_on | join('/') }}
      ansible.builtin.assert:
        that:
          - conn_ok
          - results | selectattr('status', 'in', fail_on) | list | length == 0
        fail_msg: >-
          {{ ('connection failed: ' ~ conn_error) if not conn_ok else
             (results | selectattr('status', 'in', fail_on)
                      | map(attribute='script') | join(', ')) ~ ' - see ' ~ run_dir ~ '/report.html' }}
        quiet: true
