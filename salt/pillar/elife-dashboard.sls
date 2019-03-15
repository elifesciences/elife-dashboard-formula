elife_dashboard:
    name: elife-dashboard
    
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
    uwsgi:
        services:
            elife-dashboard:
                folder: /srv/elife-dashboard
            elife-article-scheduler:
                folder: /srv/elife-article-scheduler

