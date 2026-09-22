# Set by scripts/init-service.sh. CI refuses to plan while CHANGE_ME remains.
project_name = "CHANGE_ME"
aws_region   = "CHANGE_ME"

service_name = "CHANGE_ME"
service_type = "web"
tier         = "private"

# The host port. Services share a host on the shared fleet, so it must be unique
# on the tier (the port registry enforces that). 1024-65535.
service_port = 0 # CHANGE_ME

# postgres, mysql or mongodb, or null for a service without a database. The
# environment must run it: development runs what the database engines repository
# activates; staging and production what core lists in their database_engines
# (mongodb there is a DocumentDB cluster).
database_engine = "postgres"

# Application secrets to generate. The Django blueprint expects django_secret_key.
generated_secret_names = ["django_secret_key"]
