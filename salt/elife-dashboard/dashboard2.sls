{% set app = pillar.elife_dashboard_2 %}
{% set dash = pillar.elife_dashboard %}
{% set user = pillar.elife.deploy_user.username %}


#
# db
#



#
# configure
#

configure-{{ app.name }}:
    file.managed:
        - user: {{ user }}
        - name: /srv/elife-dashboard/app.cfg
        - source: salt://elife-dashboard/config/srv-app-dashboard-app.cfg
        - template: jinja
        - watch_in:
            - service: uwsgi-app

    cmd.run:
        - user: {{ user }}
        - cwd: /srv/elife-dashboard/dashboard_2
        - name: ./install.sh
        - require:
            - file: configure-{{ app.name }}
            - install-elife-dashboard

configure-{{ app.name }}-log:
    file.managed:
        - name: /var/log/dashboard_2.log
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
        - name: /srv/elife-dashboard/dashboard_2/uwsgi.ini
        - source: salt://elife-dashboard/config/srv-{{ app.name }}-uwsgi.ini
        - template: jinja
        - require:
            - install-{{ dash.name }}

uwsgi-{{ app.name }}:
    file.managed:
        - name: /etc/init/uwsgi-{{ app.name }}.conf
        - source: salt://elife-dashboard/config/etc-init-uwsgi-elife-dashboard-2.conf
        - template: jinja
        - mode: 755

    service.running:
        - enable: True
        - require:
            - file: uwsgi-params
            - pip: uwsgi-pkg
            - file: uwsgi-app
            - {{ app.name }}-uwsgi-conf
            - {{ app.name }}-nginx-conf
            - file: app-log-file

    cmd.run:
        - name: service uwsgi-{{ app.name }} restart