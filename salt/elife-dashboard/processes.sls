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
