---
# Environment check before the real health check. Uses the same inventory,
# group_vars and credentials as healthcheck.yml, changes nothing, writes nothing
# except a temporary file it deletes again.
#
#   ./run.sh check_env.yml
#   ./run.sh check_env.yml --limit summit_pdb1
#
# Every check runs even if an earlier one fails, so one run shows everything that
# is wrong. Exit code is non-zero if any check is FAIL (WARN does not fail).

- name: Health check environment test
  hosts: oracle_db
  gather_facts: false

  tasks:
    # ------------------------------------------------------------ this server
    - name: sqlplus runs
      ansible.builtin.command:
        cmd: "timeout 30 {{ sqlplus_bin }} -V"
      environment: "{{ sqlplus_env }}"
      register: c_sqlplus
      changed_when: false
      failed_when: false
      run_once: true

    - name: Scripts directory
      ansible.builtin.find:
        paths: "{{ scripts_dir }}"
        patterns: "{{ scripts_patterns }}"
        excludes: "{{ scripts_excludes }}"
        file_type: file
      register: c_scripts
      failed_when: false
      run_once: true

    - name: Output directory is writable
      ansible.builtin.tempfile:
        path: "{{ output_base }}"
        prefix: .write_test_
      register: c_write
      failed_when: false
      run_once: true

    - name: Remove write test file
      ansible.builtin.file:
        path: "{{ c_write.path }}"
        state: absent
      when: c_write.path is defined
      run_once: true

    # ------------------------------------------------------------ per database
    - name: Work out listener host and port from dsn
      ansible.builtin.set_fact:
        c_host: "{{ hp[0] if hp else '' }}"
        c_port: "{{ hp[1] if hp else '' }}"
      vars:
        d: "{{ dsn | default('') | regex_replace('\\s+', '') }}"
        hp: >-
          {%- if d.startswith('(') -%}
          {{ [d | regex_findall('(?i)HOST=([^)]+)') | first | default(''),
              d | regex_findall('(?i)PORT=([0-9]+)') | first | default('1521')] }}
          {%- elif '/' in d or ':' in d -%}
          {%-   set m = d | regex_findall('^(?:[a-zA-Z]+://)?([^:/]+)(?::([0-9]+))?') | first | default([]) -%}
          {{ [m[0], m[1] or '1521'] if m else [] }}
          {%- else -%}
          {{ [] }}
          {%- endif -%}

    - name: Listener port reachable (TCP)
      ansible.builtin.wait_for:
        host: "{{ c_host }}"
        port: "{{ c_port | int }}"
        timeout: 5
      register: c_tcp
      when: c_host | length > 0
      ignore_errors: true          # not failed_when: false, which would reset .failed

    - name: Connect and query
      ansible.builtin.command:
        cmd: "timeout {{ connect_timeout }} {{ sqlplus_bin }} -S -L /nolog"
        stdin: |
          SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 400 TRIMOUT ON
          CONNECT {{ ora_user }}/"{{ ora_password }}"@{{ connect_id }}
          SELECT 'CONNECT_OK|' || sys_context('USERENV','SESSION_USER')
                 || '|' || sys_context('USERENV','CON_NAME')
                 || '|' || sys_context('USERENV','DB_NAME')
                 || '|' || sys_context('USERENV','DATABASE_ROLE')
                 || '|' || sys_context('USERENV','SERVER_HOST') FROM dual;
          SET TRANSACTION READ ONLY;
          SELECT 'READONLY_OK' FROM dual;
          SELECT 'DICT_OK|' || version_full FROM v$instance;
          EXIT
      environment: "{{ sqlplus_env }}"
      register: c_conn
      when: ora_password is defined and dsn is defined
      changed_when: false
      failed_when: false
      no_log: true

    # ---------------------------------------------------------------- verdict
    - name: Evaluate
      ansible.builtin.set_fact:
        checks: >-
          {%- set out = [] -%}
          {%- set sp = hostvars[ansible_play_hosts_all[0]].c_sqlplus -%}
          {%- set sc = hostvars[ansible_play_hosts_all[0]].c_scripts -%}
          {%- set wr = hostvars[ansible_play_hosts_all[0]].c_write -%}
          {%- set _ = out.append(['sqlplus', 'OK' if sp.rc == 0 else 'FAIL',
                (sp.stdout | trim).splitlines() | first if sp.rc == 0 else
                ((sp.stderr | default(sp.msg | default('')) | trim) ~ ' (sqlplus_bin=' ~ sqlplus_bin ~ ')')]) -%}
          {%- if sc.matched is not defined or (sc.skipped_paths | default({})) -%}
          {%-   set _ = out.append(['scripts_dir', 'FAIL', scripts_dir ~ ': ' ~ ((sc.skipped_paths | default({})).values() | first | default(sc.msg | default('not readable')))]) -%}
          {%- elif sc.matched == 0 -%}
          {%-   set _ = out.append(['scripts_dir', 'WARN', scripts_dir ~ ': no files matching ' ~ scripts_patterns | join(',')]) -%}
          {%- else -%}
          {%-   set _ = out.append(['scripts_dir', 'OK', scripts_dir ~ ': ' ~ sc.matched ~ ' script(s), first: ' ~ (sc.files | map(attribute='path') | sort | first | basename)]) -%}
          {%- endif -%}
          {%- set _ = out.append(['output_base', 'OK' if wr.path is defined else 'FAIL',
                output_base ~ (' is writable' if wr.path is defined else ': ' ~ (wr.msg | default('not writable')))]) -%}
          {%- set _ = out.append(['dsn', 'OK' if dsn is defined else 'FAIL',
                (dsn | regex_replace('\s+', '')) if dsn is defined else 'not set in inventory.yml']) -%}
          {%- set _ = out.append(['password', 'OK' if ora_password is defined else 'FAIL',
                'found for ' ~ inventory_hostname if ora_password is defined
                else 'no db_credentials entry "' ~ inventory_hostname ~ '" (credentials file loaded?)']) -%}
          {%- if c_host -%}
          {%-   set _ = out.append(['tcp', 'FAIL' if c_tcp.failed | default(true) else 'OK',
                  c_host ~ ':' ~ c_port ~ (' reachable' if not c_tcp.failed | default(true) else ' NOT reachable: ' ~ (c_tcp.msg | default('')) ~ ' (firewall/listener?)')]) -%}
          {%- else -%}
          {%-   set _ = out.append(['tcp', 'SKIP', 'TNS alias: resolved by sqlplus via tnsnames.ora']) -%}
          {%- endif -%}
          {%- if c_conn.stdout is not defined -%}
          {%-   set _ = out.append(['connect', 'SKIP', 'not attempted (see above)']) -%}
          {%- else -%}
          {%-   set ok = c_conn.stdout_lines | select('match', 'CONNECT_OK[|]') | first | default('') -%}
          {%-   if ok -%}
          {%-     set f = ok.split('|') -%}
          {%-     set _ = out.append(['connect', 'OK', 'as ' ~ f[1] ~ ' -> container ' ~ f[2] ~ ', DB ' ~ f[3] ~ ', ' ~ f[4] ~ ', server ' ~ f[5]]) -%}
          {%-     set ro = 'READONLY_OK' in c_conn.stdout -%}
          {%-     set _ = out.append(['read_only', 'OK' if ro else 'WARN', 'SET TRANSACTION READ ONLY works' if ro else 'failed; set read_only_session: false']) -%}
          {%-     set dict = c_conn.stdout_lines | select('match', 'DICT_OK[|]') | first | default('') -%}
          {%-     set _ = out.append(['v$ access', 'OK' if dict else 'WARN',
                    ('V$INSTANCE readable, version ' ~ dict.split('|')[1]) if dict
                    else 'cannot read V$INSTANCE: most health-check scripts need SELECT_CATALOG_ROLE or similar']) -%}
          {%-   else -%}
          {%-     set err = c_conn.stdout_lines | select('match', '(ORA|SP2|TNS)-[0-9]+') | first
                            | default('timed out after ' ~ connect_timeout ~ ' s' if c_conn.rc == 124
                                      else 'rc=' ~ c_conn.rc ~ ' ' ~ (c_conn.stderr | default('') | trim)) -%}
          {%-     set _ = out.append(['connect', 'FAIL', err]) -%}
          {%-   endif -%}
          {%- endif -%}
          {{ out }}

    - name: Result
      ansible.builtin.debug:
        msg: >-
          {%- set out = [] -%}
          {%- for c in checks -%}{%- set _ = out.append('%-4s  %-10s %s' | format(c[1], c[0], c[2])) -%}{%- endfor -%}
          {{ out }}

    - name: All required checks passed
      ansible.builtin.assert:
        that: checks | selectattr('1', 'equalto', 'FAIL') | list | length == 0
        fail_msg: "{{ checks | selectattr('1', 'equalto', 'FAIL') | map(attribute='0') | join(', ') }} failed"
        success_msg: "environment ready for healthcheck.yml"
