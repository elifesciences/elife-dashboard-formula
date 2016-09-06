{% set app = pillar.elife_article_scheduler %}
{% set dash = pillar.elife_dashboard %}

install-{{ app.name }}:
    file.directory:
        - name: /srv/{{ app.name }}
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.deploy_user.username }}

    git.latest:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: ssh://git@github.com/elifesciences/{{ app.name }}
        # note: elife-article-scheduler follows the same branch names as the dashboard
        - rev: {{ salt['elife.cfg']('project.branch', 'master') }}
        - branch: {{ salt['elife.cfg']('project.branch', 'master') }}
        - target: /srv/{{ app.name }}
        - force_fetch: True
        - force_checkout: True
        - force_reset: True
        - require:
            - file: install-{{ app.name }}


#
# db
#

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

{{ app.name }}-uwsgi-conf:
    file.managed:
        - name: /srv/{{ app.name }}/uwsgi.ini
        - source: salt://elife-dashboard/config/srv-{{ app.name }}-uwsgi.ini
        - template: jinja
        - require:
            - install-{{ app.name }}

# temporary state. 
old-uwsgi-{{ app.name }}:
    file.absent:
        - name: /etc/init.d/uwsgi-{{ app.name }}

uwsgi-{{ app.name }}:
    file.managed:
        - name: /etc/init/uwsgi-{{ app.name }}.conf
        - source: salt://elife-dashboard/config/etc-init-uwsgi-elife-article-scheduler.conf
        - template: jinja
        - mode: 755

    service.running:
        - enable: True
        - require:
            - file: old-uwsgi-{{ app.name }}
            - file: uwsgi-params
            - pip: uwsgi-pkg
            - file: uwsgi-app            
            - file: app-uwsgi-conf
            - file: app-nginx-conf
            - file: app-log-file
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
        - onlyif:
            - test -f /srv/{{ app.name }}/manage.sh
