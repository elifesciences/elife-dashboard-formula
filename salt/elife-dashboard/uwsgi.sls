app-nginx-conf:
    file.managed:
        - name: /etc/nginx/sites-enabled/app.conf
        - template: jinja
        - source: salt://elife-dashboard/config/etc-nginx-sitesenabled-app.conf
        - require:
            - cmd: create-production-web-user
            {% if pillar.elife.env != 'dev' %}
            - cmd: web-ssl-enabled
            {% endif %}

{% if salt['elife.cfg']('cfn.outputs.DomainName') %}
dashboard-unencrypted-redirect:
    file.symlink:
        - name: /etc/nginx/sites-enabled/unencrypted-redirect.conf
        - target: /etc/nginx/sites-available/unencrypted-redirect.conf
        - require:
            - app-nginx-conf
{% endif %}

app-uwsgi-conf:
    file.managed:
        - name: /srv/app/uwsgi.ini
        - source: salt://elife-dashboard/config/srv-elife-dashboard-uwsgi.ini
        - template: jinja
        - require:
            - install-elife-dashboard

old-uwsgi-app:
    file.absent:
        - name: /etc/init.d/uwsgi-app

uwsgi-app:
    file.managed:
        - name: /etc/init/uwsgi-app.conf
        - source: salt://elife-dashboard/config/etc-init-uwsgi-app.conf
        - mode: 755

    service.running:
        - enable: True
        - require:
            - file: uwsgi-params
            - pip: uwsgi-pkg
            - file: uwsgi-app
            - file: app-uwsgi-conf
            - file: app-nginx-conf
            - file: app-log-file
        - watch:
            - install-elife-dashboard
            # restart uwsgi if nginx service changes 
            - service: nginx-server-service

