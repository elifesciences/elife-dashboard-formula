{% set app = pillar.elife_article_scheduler %}
{% set dash = pillar.elife_dashboard %}

install-{{ app.name }}:
    git.latest:
        - name: ssh://git@github.com/elifesciences/{{ app.name }}
        - identity: {{ pillar.elife.projects_builder.key or '' }}
        # note: elife-article-scheduler is always deployed as master
        # lsh 2019-03-18: lets not muck about here
        # build vars 'branch' is pinned at 'develop'. 
        # development is happening in master
        # article-scheduler has no pinned version support whatsoever
        # using build vars:
        #- rev: {{ salt['elife.cfg']('project.branch', 'master') }}
        #- branch: {{ salt['elife.cfg']('project.branch', 'master') }}
        - rev: master
        - branch: master
        - target: /srv/{{ app.name }}
        - force_fetch: True
        - force_checkout: True
        - force_reset: True

    file.directory:
        - name: /srv/{{ app.name }}
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.deploy_user.username }}
        - recurse:
            - user
            - group
        - require:
            - git: install-{{ app.name }}

    cmd.run:
        - name: ./install.sh
        - cwd: /srv/{{ app.name }}
        - user: {{ pillar.elife.deploy_user.username }}
        - require:
            - file: install-{{ app.name }}

#
# db
#

# ensure local postgresql is running
# when an rds instance is detected, the local service is stopped
# article-scheduler is an exception to that rule
extend:
    postgresql:
        service:
            - running
            - enable: True

# copied from builder-base-formula/elife/postgresql.sls as it is not
# executed there due to RDS being in use
postgresql-user-article-scheduler-hack:
    postgres_user.present:
        - name: {{ pillar.elife.db_root.username }}
        - password: {{ pillar.elife.db_root.password }}
        - refresh_password: True
        #- db_host: localhost
        - db_password: {{ pillar.elife.db_root.password }}
        # doesn't work on RDS instances
        - superuser: True
        - login: True

{{ app.name }}-db-user:
    postgres_user.present:
        - name: {{ app.db.username }}
        - encrypted: True
        - password: {{ app.db.password }}
        - refresh_password: True
        
        - db_host: localhost
        - db_user: {{ pillar.elife.db_root.username }}
        - db_password: {{ pillar.elife.db_root.password }}
        #{% if salt['elife.cfg']('cfn.outputs.RDSHost') %}
        #- db_host: {{ salt['elife.cfg']('cfn.outputs.RDSHost') }}
        #- db_port: {{ salt['elife.cfg']('cfn.outputs.RDSPort') }}
        #{% endif %}
        - require:
            - service: postgresql
            - postgresql-user-article-scheduler-hack

{{ app.name }}-db-exists:
    postgres_database.present:
        - name: {{ app.db.name }}
        - owner: {{ app.db.username }}
        - owner_recurse: true
        - db_host: localhost
        - db_port: 5432
        - db_user: {{ pillar.elife.db_root.username }}
        - db_password: {{ pillar.elife.db_root.password }}
        - require:
            - postgres_user: {{ app.name }}-db-user

#
# configure
#

configure-{{ app.name }}:
    file.managed:
        - name: /srv/{{ app.name }}/src/core/settings.py
        - source:
            - salt://elife-dashboard/config/srv-{{ app.name }}-src-core-{{ pillar.elife.env }}_settings.py
            - salt://elife-dashboard/config/srv-{{ app.name }}-default_settings.py
        - user: {{ pillar.elife.deploy_user.username }}
        - force: True
        - template: jinja
        - require:
            - install-{{ app.name }}
            - postgres_database: {{ app.name }}-db-exists

    # command collects css/js/fonts/etc in to a single place
    cmd.run:
        - cwd: /srv/{{ app.name }}/
        - name: ./manage.sh collectstatic --noinput
        - user: {{ pillar.elife.deploy_user.username }}
        - require:
            - file: configure-{{ app.name }}

configure-{{ app.name }}-log:
    file.managed:
        - name: /srv/{{ app.name }}/src/elife-article-scheduler.log
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 664
        - require:
            - file: configure-{{ app.name }}

#
# backup
# bit of a hack for article-scheduler

# separate descriptor living in different config directory so it doesn't conflict with elife-dashboard ubr config
ubr-{{ app.name }}-db-backup:
    file.managed:
        - name: /etc/ubr2/elife-article-scheduler-backup.yaml
        - source: salt://elife-dashboard/config/etc-ubr2-elife-article-scheduler-backup.yaml
        - makedirs: true
        - template: jinja
        - require:
            - {{ app.name }}-db-exists

# separate UBR config living alongside regular config
elife-article-scheduler-ubr-config:
    file.managed:
        - name: /opt/ubr/elife-article-scheduler-app.cfg
        - source: salt://elife-dashboard/config/opt-ubr-elife-article-scheduler-app.cfg
        - template: jinja
        # read-write for root only
        - user: root
        - group: root
        - mode: 600
        - require:
            - install-ubr

# 11:15pm every day
{{ app.name }}-daily-backups:
    # only backup prod, end2end, adhoc and continuumtest instances
    {% if pillar.elife.env in ['dev', 'ci'] %}
    cron.absent:
    {% else %}
    cron.present:
    {% endif %}
        - user: root
        - identifier: daily-{{ app.name }}-backups
        - name: cd /opt/ubr/ && UBR_CFG_FILE=elife-article-scheduler-app.cfg ./ubr.sh >> /var/log/ubr-cron.log
        - minute: 15 # original in builder-base/backup-cron.sls is '0'
        - hour: 23
        - require:
            - install-ubr

#
# webserver
#

{{ app.name }}-nginx-conf:
    file.managed:
        - name: /etc/nginx/sites-enabled/{{ app.name }}.conf
        - template: jinja
        - source: salt://elife-dashboard/config/etc-nginx-sitesenabled-{{ app.name }}.conf
        - require:
            - cmd: create-production-web-user
        - listen_in:
            - service: nginx-server-service

{{ app.name }}-uwsgi-conf:
    file.managed:
        - name: /srv/{{ app.name }}/uwsgi.ini
        - source: salt://elife-dashboard/config/srv-{{ app.name }}-uwsgi.ini
        - template: jinja
        - require:
            - install-{{ app.name }}

uwsgi-elife-article-scheduler-upstart:
    file.managed:
        - name: /etc/init/uwsgi-{{ app.name }}.conf
        - source: salt://elife-dashboard/config/etc-init-uwsgi-elife-article-scheduler.conf
        - template: jinja
        - mode: 755

{% if salt['grains.get']('osrelease') != "14.04" %}
uwsgi-{{ app.name }}.socket:
    service.running:
        - enable: True
        - require_in: uwsgi-{{ app.name }}
{% endif %}

uwsgi-{{ app.name }}:
    service.running:
        - enable: True
        - require:
            - uwsgi-pkg
            - uwsgi-elife-article-scheduler-upstart
            - {{ app.name }}-uwsgi-conf
            - {{ app.name }}-uwsgi-conf
            - {{ app.name }}-nginx-conf
            - configure-{{ app.name }}-log
        - watch:
            - install-{{ app.name }}
            # restart uwsgi if nginx service changes
            - service: nginx-server-service

# publish articles every minute
publish-articles-cron:
    cron.present:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: cd /srv/{{ app.name }}/ && ./manage.sh publish_articles
        - identifier: publish-articles-every-minute
        - minute: '*'
        - require:
            - file: configure-{{ app.name }}
