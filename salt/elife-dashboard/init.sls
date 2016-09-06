{% set app = pillar.elife_dashboard %}
{% set user = pillar.elife.deploy_user.username %}
{% set webuser = pillar.elife.webserver.username %}

install-{{ app.name }}:
    builder.git_latest:
        - name: git@github.com:elifesciences/elife-dashboard.git
        - identity: {{ pillar.elife.projects_builder.key or '' }}
        - rev: {{ salt['elife.rev']() }}
        - branch: {{ salt['elife.branch']() }}
        - target: /srv/elife-dashboard
        - force_fetch: True
        - force_checkout: True
        - force_reset: True
        - fetch_pull_requests: True

    file.directory:
        - name: /srv/elife-dashboard
        - user: {{ user }}
        - group: {{ user }}
        - recurse:
            - user
            - group
        - require:
            - builder: install-elife-dashboard

npm-install:
    cmd.run:
        - name: npm install
        - cwd: /srv/elife-dashboard
        - user: {{ user }}
        - require:
            - install-elife-dashboard
            - nodejs


app-link:
    cmd.run:
        - cwd: /srv/
        - name: ln -sfT elife-dashboard app
        - require:
            - install-elife-dashboard

configure-{{ app.name }}:
    file.managed:
        - user: {{ user }}
        - name: /srv/app/settings.py
        - source:
            - salt://elife-dashboard/config/srv-app-dashboard-{{ pillar.elife.env }}_settings.py
            - salt://elife-dashboard/config/srv-app-dashboard-default_settings.py
        - template: jinja
        - watch_in:
            - service: uwsgi-app

    cmd.run:
        - user: {{ user }}
        - cwd: /srv/elife-dashboard/
        - name: ./install.sh
        - require:
            - file: configure-{{ app.name }}
            - install-elife-dashboard

#
# auth
#

# credentials for the production guys to use
create-production-web-user:
    cmd.run:
        - name: sudo htpasswd -b -c /etc/nginx/.production-htpasswd {{ app.basic_auth.username }} {{ app.basic_auth.password }}
        - require:
            - pkg: nginx-server

aws-credentials:
    file.managed:
        - user: www-data
        - group: www-data
        - name: /var/www/.aws/credentials
        - source: salt://elife/templates/aws-credentials
        - context:
            access_id: {{ app.aws.access_id }}
            secret_access_key: {{ app.aws.secret_access_key }}
        - template: jinja
        - makedirs: True


#
# logging
#

app-log-file:
    file.managed:
        - name: /var/log/app.log
        - user: {{ webuser }}
        - group: {{ webuser }}
        - mode: 660


app-syslog-conf:
    file.managed:
        - name: /etc/syslog-ng/conf.d/app.conf
        - source: salt://elife-dashboard/config/etc-syslog-ng-conf.d-app.conf
        - template: jinja
        - require:
            - pkg: syslog-ng
            - file: app-log-file
        - listen_in:
            - service: syslog-ng

process-queue-daemon-log-file:
    file.managed:
        - name: /var/log/process-queue-daemon.log
        - user: {{ user }}
        - group: {{ user }}

#
# db
#

app-db-user:
    postgres_user.present:
        - name: {{ app.db.username }}
        - encrypted: True
        - password: {{ app.db.password }}
        - refresh_password: True
        - db_user: {{ pillar.elife.db_root.username }}
        {% if salt['elife.cfg']('cfn.outputs.RDSHost') %}
        - db_password: {{ salt['elife.cfg']('project.rds_password') }}
        - db_host: {{ salt['elife.cfg']('cfn.outputs.RDSHost') }}
        - db_port: {{ salt['elife.cfg']('cfn.outputs.RDSPort') }}
        {% else %}
        - db_password: {{ pillar.elife.db_root.password }}
        {% endif %}
        - createdb: True

app-db-exists:
    postgres_database.present:
        - name: {{ app.db.name }}
        - owner: {{ app.db.username }}
        - db_user: {{ app.db.username }}
        - db_password: {{ app.db.password }}
        {% if salt['elife.cfg']('cfn.outputs.RDSHost') %}
        - db_host: {{ salt['elife.cfg']('cfn.outputs.RDSHost') }}
        - db_port: {{ salt['elife.cfg']('cfn.outputs.RDSPort') }}
        {% endif %}

        - require:
            - postgres_user: app-db-user

load-db-schema:
    cmd.run:
        - cwd: /srv/elife-dashboard/dashboard/
        - env:
            - PGPASSWORD: {{ app.db.password }}
        - name: |
            set -e 
            psql --host={{ salt['elife.cfg']('cfn.outputs.RDSHost') or app.db.host }} \
                --port={{ salt['elife.cfg']('cfn.outputs.RDSPort') or app.db.port }} \
                --username={{ app.db.username }} \
                --no-password \
                {{ app.db.name }} < db/create_monitor_dashboard.sql
            touch /root/db-created.flag
        - unless:
            - test -f /root/db-created.flag
        - require:
            - postgres_database: app-db-exists

# hook to allow the general purpose daemon code to do it's thing
app-done:
    cmd.run: 
        - name: echo "app is done installing"
        - require:
            - cmd: load-db-schema
            - cmd: configure-{{ app.name }}
            - cmd: npm-install

#
# process queue
#

{{ app.name }}-process-queue-daemon:
    file.managed:
        - name: /etc/init/{{ app.name }}-process-queue-daemon.conf
        - source: salt://elife-dashboard/config/etc-init-elife-dashboard-process-queue-daemon.conf
        - template: jinja
        - require:
            - cmd: app-done

{{ app.name }}-process-queue-daemons-task:
    file.managed:
        - name: /etc/init/{{ app.name }}-process-queue-daemons.conf
        - source: salt://elife/config/etc-init-multiple-processes.conf
        - template: jinja
        - context:
            process: {{ app.name }}-process-queue-daemon
            number: 5
        - require:
            - file: {{ app.name }}-process-queue-daemon
