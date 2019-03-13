{% set app = pillar.elife_article_scheduler %}
{% set dash = pillar.elife_dashboard %}

install-{{ app.name }}:
    git.latest:
        - name: ssh://git@github.com/elifesciences/{{ app.name }}
        - identity: {{ pillar.elife.projects_builder.key or '' }}
        # note: elife-article-scheduler is always deployed as master
        # until it has its own instance, we cannot a revision
        # using build vars
        - rev: {{ salt['elife.cfg']('project.branch', 'master') }}
        - branch: {{ salt['elife.cfg']('project.branch', 'master') }}
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
        - cwd: /srv/{{ app.name }}
        - name: ./install.sh
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

{{ app.name }}-db-user:
    postgres_user.present:
        - name: {{ app.db.username }}
        - encrypted: True
        - password: {{ app.db.password }}
        - refresh_password: True
        
        - db_user: {{ pillar.elife.db_root.username }}
        - db_password: {{ pillar.elife.db_root.password }}
        #{% if salt['elife.cfg']('cfn.outputs.RDSHost') %}
        #- db_host: {{ salt['elife.cfg']('cfn.outputs.RDSHost') }}
        #- db_port: {{ salt['elife.cfg']('cfn.outputs.RDSPort') }}
        #{% endif %}
        - require:
            - service: postgresql

{{ app.name }}-db-exists:
    postgres_database.present:
        - name: {{ app.db.name }}
        - owner: {{ app.db.username }}
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

configure-{{ app.name }}-log:
    file.managed:
        - name: /srv/{{ app.name }}/src/elife-article-scheduler.log
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 664
        - require:
            - file: configure-{{ app.name }}

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

uwsgi-elife-article-scheduler-systemd:
    file.managed:
        - name: /lib/systemd/system/uwsgi-{{ app.name }}.service
        - source: salt://elife-dashboard/config/lib-systemd-system-uwsgi-elife-article-scheduler.service
        - template: jinja

uwsgi-{{ app.name }}:
    service.running:
        - enable: True
        - require:
            - uwsgi-pkg
            - uwsgi-elife-article-scheduler-upstart
            - uwsgi-elife-article-scheduler-systemd
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
