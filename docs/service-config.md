# The service config

This repository publishes one SSM parameter per service:

```text
/<project>/services/<service>/config        (String, JSON)
```

It is the **only** thing that passes from this repository to the application repository. This repository's role writes it; the application repository's role reads it. It holds identifiers only, never a secret value.

## Shape (schema_version 1)

```json
{
  "schema_version": 1,
  "service_name": "auth",
  "service_type": "web",
  "environment": "development",
  "tier": "private",
  "hosting_model": "shared",
  "domain": "auth.dev.example.org",
  "port": 1024,
  "health_check_path": "/health",
  "secret": { "arn": "arn:aws:secretsmanager:...", "name": "acme-auth-development-secret-vault" },
  "ecr": { "repository_url": "123456789012.dkr.ecr.eu-west-1.amazonaws.com/auth/web", "repository_name": "auth/web" },
  "target_group_arn": "arn:aws:elasticloadbalancing:...",
  "deploy": { "bucket": "acme-development-deploy", "prefix": "private/auth", "update_document": "acme-fleet-update" },
  "static": { "bucket": "acme-development-assets", "prefix": "static/auth" },
  "database": {
    "engine": "postgres",
    "host": "db.dev.example.org",
    "port_parameter": "/acme/database/engines/postgres/port",
    "secret_fields": { "name": "db_name", "user": "db_user", "password": "db_password" }
  }
}
```

| Field | The application repository uses it to |
| --- | --- |
| `ecr.repository_url` | push and name its image |
| `deploy.bucket`, `deploy.prefix` | publish `docker-compose.yml` and `.env` to `s3://<bucket>/<prefix>/` |
| `deploy.update_document` | redeploy: send this SSM document to the tier's hosts, and nothing else |
| `static.bucket`, `static.prefix` | upload static files to `s3://<bucket>/<prefix>/`; the application's `STATIC_URL` is `/static/<service>/` |
| `port` | fill `__PORT__` in the compose file |
| `domain` | set the allowed host and CSRF origin |
| `secret.arn` | fill `__APP_SECRET_ARN__` in `.env` |
| `database.*` | reach the database. The **port** is not here: the platform team publishes each engine's port under `port_parameter`, so read it from there at deploy time |

`database` is `null` for a service without one. In a `dedicated` environment `deploy` differs (each service has its own bucket); this version does not host those.

## Changing it

Adding a field is compatible. Renaming or removing one, or changing its meaning, bumps `schema_version`, and the application repository checks the version it was written for. The parameter must stay under 4,096 characters, which the module enforces.
