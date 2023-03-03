{% set app = pillar.elife_dashboard %}
application_port = None
preview_base_url = "{{ app.preview_base_url }}" # # used as read only, for generating links

# Article scheduler settings
article_scheduler_url = 'http://localhost:8080/schedule/v1/article_scheduled_status/'
article_schedule_publication_url = 'http://localhost:8080/schedule/v1/schedule_article_publication/'
article_schedule_range_url = 'http://localhost:8080/schedule/v1/article_schedule_for_range/from/<from>/to/<to>/'

# SQS settings
sqs_region = "us-east-1"
event_monitor_queue = "{{ app.event_monitor_queue }}"
workflow_starter_queue = "{{ app.workflow_starter_queue }}"
event_queue_pool_size = 5
event_queue_message_count = 5

aws_access_key_id = "{{ pillar.elife_dashboard.aws.access_id }}"
aws_secret_access_key = "{{ pillar.elife_dashboard.aws.secret_access_key }}"

# Logging
log_level = "{{ app.log_level }}"
log_file = "/var/log/app.log"
process_queue_log_file = "/var/log/process-queue-daemon.log"

# Database
database = "{{ app.db.name }}"
host = "{{ salt['elife.cfg']('cfn.outputs.RDSHost') or app.db.host }}"
port = "{{ salt['elife.cfg']('cfn.outputs.RDSPort') or app.db.port }}"
user = "{{ app.db.username }}"
password = "{{ app.db.password }}"

