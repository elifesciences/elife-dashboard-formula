{% if salt['grains.get']('oscodename') == 'trusty' %}
elife-dashboard-process-queue-daemons-task:
    file.managed:
        - name: /etc/init/elife-dashboard-process-queue-daemons.conf
        - source: salt://elife/config/etc-init-multiple-processes.conf
        - template: jinja
        - context:
            process: elife-dashboard-process-queue-daemon
            number: 5
        - require:
            - file: elife-dashboard-process-queue-daemon

elife-dashboard-process-queue-daemons-start:
    cmd.run:
        - name: start elife-dashboard-process-queue-daemons
        - require:
            - file: elife-dashboard-process-queue-daemons-task
        - watch:
            - install-elife-dashboard

{% else %}

{% set pname = "elife-dashboard-process-queue-daemon" %}
{% set controller = "elife-dashboard-process-queue-daemons" %}

# template service
{{ pname }}-service-template:
    file.managed:
        - name: /lib/systemd/system/{{ pname }}@.service
        - source: salt://elife-dashboard/config/lib-systemd-system-{{ pname }}@.service
        - template: jinja

# script to control template service
{{ controller }}-script:
    file.managed:
        - name: /opt/{{ controller }}.sh
        - source: salt://elife/templates/systemd-multiple-processes.sh
        - template: jinja
        - mode: 755
        - context:
            process: {{ pname }}
            number: 5

# service to run controller script
{{ controller }}-service:
    file.managed:
        - name: /lib/systemd/system/{{ controller }}.service
        - source: salt://elife-dashboard/config/lib-systemd-system-{{ controller }}.service

    service.running:
        - name: {{ controller }}
        - require:
            - {{ controller }}-script
            - {{ pname }}-service-template
            - file: {{ controller }}-service
        - watch:
            - install-elife-dashboard

{% endif %}
