app-nginx-conf:
    file.managed:
        - name: /etc/nginx/sites-enabled/app.conf
        - template: jinja
        - source: salt://elife-dashboard/config/etc-nginx-sitesenabled-app.conf
        - require:
            - cmd: create-production-web-user
            - uwsgi-params # builder-base.uwsgi-params
            {% if pillar.elife.env != 'dev' %}
            - cmd: web-ssl-enabled
            {% endif %}
        - listen_in:
            - service: nginx-server-service

{% if salt['elife.cfg']('cfn.outputs.DomainName') %}
# we use HSTS for the redirection
# we typically have port 80 closed externally and allow unencrypted internally
dashboard-unencrypted-redirect:
    file.absent:
        - name: /etc/nginx/sites-enabled/unencrypted-redirect.conf
{% endif %}

app-uwsgi-conf:
    file.managed:
        - name: /srv/elife-dashboard/uwsgi.ini
        - source: salt://elife-dashboard/config/srv-elife-dashboard-uwsgi.ini
        - template: jinja
        - require:
            - install-elife-dashboard

uwsgi-elife-dashboard.socket:
    service.running:
        - enable: True

uwsgi-elife-dashboard:
    service.running:
        - enable: True
        - require:
            - uwsgi-params
            - uwsgi-elife-dashboard.socket
            - app-uwsgi-conf
            - app-nginx-conf
            - app-log-file
        - watch:
            - install-elife-dashboard
            # restart uwsgi if nginx service changes 
            - service: nginx-server-service

