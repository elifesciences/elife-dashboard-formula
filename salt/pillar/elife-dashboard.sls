elife_dashboard:
    name: elife-dashboard
    publishing_service: http://localhost/api/queue_article_publication

    preview_base_url: https://elifesciences.org/
    log_level: INFO # DEBUG, INFO, WARN, ERROR
    event_monitor_queue:
    workflow_starter_queue:

    aws:
        username: null
        access_id: null
        secret_access_key: null

    db:
        name: elifemonitoring
        username: elifemonitoring # case sensitive. use all lower
        password: elifemonitoring
        host: 127.0.0.1
        port: 5432

    basic_auth:
        username: username
        password: password
        # created with `caddy hash-password`
        caddy_password_hash: "$2a$14$jeFTFIY1bTwOcu9wukSMNOOwr0520Z46lywGMZ2jkiIysZtrCkzrW"

elife_article_scheduler:
    name: elife-article-scheduler

    secret_key: "django-secret-key-do-not-use-in-prod"

    db:
        name: articlescheduler
        username: articlescheduler
        password: articlescheduler
        host: 127.0.0.1
        port: 5432

    web:
        port: 8080

elife_dashboard_2:
    name: elife-dashboard-2
    preview_base_url: https://foo.test.org
    secret_key: "django-secret-key-do-not-use-in-prod"
    web:
        port: 8081

elife:
    webserver:
        app: caddy

    uwsgi:
        services:
            elife-dashboard:
                folder: /srv/elife-dashboard
                protocol: http-socket
            elife-article-scheduler:
                folder: /srv/elife-article-scheduler
                protocol: http-socket
