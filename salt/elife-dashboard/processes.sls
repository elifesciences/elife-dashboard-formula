elife-dashboard-process-queue-daemons-start:
    cmd.run:
        - name: start elife-dashboard-process-queue-daemons
        - require:
            - file: elife-dashboard-process-queue-daemons-task
        - watch:
            - install-elife-dashboard
