install-elife-article-scheduler:
    git.latest:
        - name: ssh://git@github.com/elifesciences/elife-article-scheduler
        - identity: {{ pillar.elife.projects_builder.key or '' }}
        # lsh 2019-03-18: elife-article-scheduler is always deployed as master
        # build vars 'branch' is pinned at 'develop'. 
        # development is happening in master
        # article-scheduler has no pinned version support whatsoever
        # using build vars:
        #- rev: {{ salt['elife.cfg']('project.branch', 'master') }}
        #- branch: {{ salt['elife.cfg']('project.branch', 'master') }}
        - rev: master
        - branch: master
        - target: /srv/elife-article-scheduler
        - force_fetch: True
        - force_checkout: True
        - force_reset: True

    file.directory:
        - name: /srv/elife-article-scheduler
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.deploy_user.username }}
        - recurse:
            - user
            - group
        - require:
            - git: install-elife-article-scheduler

    cmd.run:
        - name: ./install.sh
        - cwd: /srv/elife-article-scheduler
        - runas: {{ pillar.elife.deploy_user.username }}
        - require:
            - file: install-elife-article-scheduler

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
        - name: {{ pillar.elife.db.root.username }}
        - password: {{ pillar.elife.db.root.password }}
        - refresh_password: True
        #- db_host: localhost
        - db_password: {{ pillar.elife.db.root.password }}
        # doesn't work on RDS instances
        - superuser: True
        - login: True

elife-article-scheduler-db-user:
    postgres_user.present:
        - name: {{ pillar.elife_article_scheduler.db.username }}
        - encrypted: scram-sha-256
        - password: {{ pillar.elife_article_scheduler.db.password }}
        - refresh_password: True
        
        - db_host: localhost
        - db_user: {{ pillar.elife.db.root.username }}
        - db_password: {{ pillar.elife.db.root.password }}
        - require:
            - service: postgresql
            - postgresql-user-article-scheduler-hack

elife-article-scheduler-db-exists:
    postgres_database.present:
        - name: {{ pillar.elife_article_scheduler.db.name }}
        - owner: {{ pillar.elife_article_scheduler.db.username }}
        - owner_recurse: true
        - db_host: localhost
        - db_port: 5432
        - db_user: {{ pillar.elife.db.root.username }}
        - db_password: {{ pillar.elife.db.root.password }}
        - require:
            - postgres_user: elife-article-scheduler-db-user

#
# configure
#

configure-elife-article-scheduler:
    file.managed:
        - name: /srv/elife-article-scheduler/app.cfg
        - source: salt://elife-dashboard/config/srv-elife-article-scheduler-app.cfg
        - user: {{ pillar.elife.deploy_user.username }}
        - force: True
        - follow_symlinks: False
        - template: jinja
        - require:
            - install-elife-article-scheduler

    # command collects css/js/fonts/etc in to a single place
    cmd.run:
        - cwd: /srv/elife-article-scheduler/
        - name: ./manage.sh collectstatic --noinput
        - runas: {{ pillar.elife.deploy_user.username }}
        - require:
            - file: configure-elife-article-scheduler
            - elife-article-scheduler-db-exists

configure-elife-article-scheduler-log:
    file.managed:
        - name: /srv/elife-article-scheduler/src/elife-article-scheduler.log
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 664
        - require:
            - file: configure-elife-article-scheduler

#
# backup
# bit of a hack for article-scheduler
#

# separate descriptor living in different config directory so it doesn't conflict with elife-dashboard ubr config
ubr-elife-article-scheduler-db-backup:
    file.managed:
        - name: /etc/ubr2/elife-article-scheduler-backup.yaml
        - source: salt://elife-dashboard/config/etc-ubr2-elife-article-scheduler-backup.yaml
        - makedirs: true
        - template: jinja

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
elife-article-scheduler-daily-backups:
    # only backup prod, end2end, adhoc and continuumtest instances
    {% if pillar.elife.env in ['dev', 'ci'] %}
    cron.absent:
    {% else %}
    cron.present:
    {% endif %}
        - user: root
        - identifier: daily-elife-article-scheduler-backups
        - name: cd /opt/ubr/ && UBR_CFG_FILE=elife-article-scheduler-app.cfg ./ubr.sh >> /var/log/ubr-cron.log
        - minute: 15 # original in builder-base/backup-cron.sls is '0'
        - hour: 23
        - require:
            - install-ubr

#
# webserver
#

elife-article-scheduler-nginx-conf:
    file.managed:
        - name: /etc/nginx/sites-enabled/elife-article-scheduler.conf
        - template: jinja
        - source: salt://elife-dashboard/config/etc-nginx-sitesenabled-elife-article-scheduler.conf
        - require:
            - cmd: create-production-web-user
        - listen_in:
            - service: nginx-server-service

elife-article-scheduler-uwsgi-conf:
    file.managed:
        - name: /srv/elife-article-scheduler/uwsgi.ini
        - source: salt://elife-dashboard/config/srv-elife-article-scheduler-uwsgi.ini
        - template: jinja
        - require:
            - install-elife-article-scheduler

uwsgi-elife-article-scheduler.socket:
    service.running:
        - enable: True
        - require_in: uwsgi-elife-article-scheduler

uwsgi-elife-article-scheduler:
    service.running:
        - enable: True
        - require:
            - uwsgi-pkg
            - elife-article-scheduler-uwsgi-conf
            - elife-article-scheduler-uwsgi-conf
            - elife-article-scheduler-nginx-conf
            - configure-elife-article-scheduler-log
        - watch:
            - install-elife-article-scheduler
            # restart uwsgi if nginx service changes
            - service: nginx-server-service

# publish articles every minute
publish-articles-cron:
    cron.present:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: cd /srv/elife-article-scheduler/ && ./manage.sh publish_articles
        - identifier: publish-articles-every-minute
        - minute: '*'
        - require:
            - file: configure-elife-article-scheduler
