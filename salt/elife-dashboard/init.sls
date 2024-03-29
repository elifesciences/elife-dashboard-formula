# 2019-03-15, note: this was an attempt to make the installation and configuration of python web apps more generic with 
# an eye to replacing their formula with a single universal one managed 

{% set app = pillar.elife_dashboard %}
{% set user = pillar.elife.deploy_user.username %}
{% set webuser = pillar.elife.webserver.username %}
{% set osrelease = salt['grains.get']('oscodename') %}
{% set db_root_user = salt['elife.cfg']('project.rds_username', pillar.elife.db.root.username) %}
{% set db_root_pass = salt['elife.cfg']('project.rds_password', pillar.elife.db.root.password) %}

install-elife-dashboard:
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

    # thanks to node_modules containing 40K files, file.directory is too slow
    cmd.run:
        - name: chown -R {{ user }}:{{ user }} .
        - cwd: /srv/elife-dashboard
        - require:
            - builder: install-elife-dashboard

configure-elife-dashboard:
    file.managed:
        - user: {{ user }}
        - name: /srv/elife-dashboard/settings.py
        - source: salt://elife-dashboard/config/srv-elife-dashboard-settings.py
        - template: jinja
        - require:
            - install-elife-dashboard
        - watch_in:
            - service: uwsgi-elife-dashboard

configure-elife-dashboard-test:
    file.absent:
        - name: /srv/elife-dashboard/settings_test.py

install-js:
    cmd.run:
        - cwd: /srv/elife-dashboard
        - name: ./install-js.sh
        - runas: {{ user }}
        - require:
            - install-elife-dashboard
            - nodejs16
        # only run if `builder.git_latest` of `install-elife-dashboard` made changes
        # 2020-12-04: added to stop the occasional 'npm install' command from failing
        - onlyif:
            - builder: install-elife-dashboard

install-python:
    cmd.run:
        - runas: {{ user }}
        - cwd: /srv/elife-dashboard/
        - name: ./install.sh
        - require:
            - uwsgi-pkg # builder-base.uwsgi , gcc is required to install uwsgi via pip
            - file: configure-elife-dashboard
            - install-elife-dashboard

#
# auth
#

{% if pillar.elife.webserver.app != "caddy" %}
# credentials for the production guys to use
create-production-web-user:
    cmd.run:
        - name: sudo htpasswd -b -c /etc/nginx/.production-htpasswd {{ app.basic_auth.username }} {{ app.basic_auth.password }}
        - require:
            - pkg: nginx-server
{% endif %}

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

app-log-file-logrotate:
    file.managed:
        - name: /etc/logrotate.d/app-log
        - source: salt://elife-dashboard/config/etc-logrotate.d-app-log

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
# lsh@2022-06-24: I think a chunk of the below became builder-base-formula/salt/elife/postgresql-appdb.sls
#

app-db-user:
    postgres_user.present:
        - name: {{ app.db.username }}
        - encrypted: scram-sha-256
        - password: {{ app.db.password }}
        - refresh_password: True
        - db_user: {{ db_root_user }}
        - db_password: {{ db_root_pass }}
        {% if salt['elife.cfg']('cfn.outputs.RDSHost') %}
        - db_host: {{ salt['elife.cfg']('cfn.outputs.RDSHost') }}
        - db_port: {{ salt['elife.cfg']('cfn.outputs.RDSPort') }}
        {% endif %}
        - createdb: True

app-db-exists:
    postgres_database.present:
        - name: {{ app.db.name }}
        - owner: {{ app.db.username }}
        - db_user: {{ db_root_user }}
        - db_password: {{ db_root_pass }}
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
            - install-elife-dashboard
            - postgres_database: app-db-exists

db-perms-to-rds_superuser:
    cmd.script:
        - name: salt://elife/scripts/rds-perms.sh
        - template: jinja
        - defaults:
            user: {{ app.db.username }}
            pass: {{ app.db.password }}
            otherdb: {{ app.db.name }}
        - require:
            - load-db-schema

ubr-app-db-backup:
    file.managed:
        - name: /etc/ubr/elife-dashboard-backup.yaml
        - source: salt://elife-dashboard/config/etc-ubr-elife-dashboard-backup.yaml
        - template: jinja
        - require:
            - load-db-schema

#
# testing
#

{% if pillar.elife.env in ["dev", "ci", "end2end"] %}
# lsh@2021-03-18: the headless browser installed by npm for the JS tests is no longer maintained or incompatible or
# something. Remove when JS can run its tests headless/is less fubar.
chromium:
    pkg.installed:
        - name: chromium-browser
{% endif %}

#
#
#

# hook to allow the general purpose daemon code to do it's thing
app-done:
    cmd.run: 
        - name: echo "app is done installing"
        - require:
            - load-db-schema
            - configure-elife-dashboard
            - install-js
            - install-python

