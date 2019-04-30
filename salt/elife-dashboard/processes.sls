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
        - enable: True
        - require:
            - {{ controller }}-script
            - {{ pname }}-service-template
            - file: {{ controller }}-service
        - watch:
            - install-elife-dashboard
            - aws-credentials
