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
# (mongodb is not available there until core's DocumentDB module exists).
database_engine = "postgres"

# Application secrets to generate. The Django blueprint expects django_secret_key.
generated_secret_names = ["django_secret_key"]

################################################################################
# THE SERVICE'S OWN HOSTS
################################################################################

min_size         = 1
desired_capacity = 1
max_size         = 2

# At least one host is always on demand; the rest are spot.
on_demand_base_capacity                  = 1
on_demand_percentage_above_base_capacity = 0
