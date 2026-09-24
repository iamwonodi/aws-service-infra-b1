# agents.json

The service team's own people. Each **agent** gets a database login on **this service's database only**, and nothing else. **It ships empty (`{}`)**; `agents.example.json` shows the shape.

| Field | Required | Meaning |
| --- | --- | --- |
| key | yes | A short name: lowercase letters and digits, starting with a letter. Their login is `<database>.<name>`, the service's database name (its name with underscores), a dot, the name. The whole login is at most 32 characters (MySQL's limit), so a long service name allows a shorter agent name; the plan says how long |
| `email` | yes | Their sign-in to the team tools, and where the invitation goes. Unique |
| `access` | yes | `read` (look at and query data) or `write` (also add, change and delete rows). Neither can change tables: that is the service's migrations' job |

Agents need a database: listing them for a service without `database_engine` fails the plan.

**Adding someone:** add their entry and apply. A password is generated and kept in the service's own secret, under `agents` (a JSON object of name, password and access). The service team's administrator hands the person their own password over a private channel; the application never sees it (its env file names only the entries it needs). The login is created when the apply provisions the service's database. They also get a sign-in to the team tools: the service declares their email to core's front door (`front-door/<service>.json` in the deploy bucket), and Cognito emails them an invitation. At their first sign-in they choose a password and set up an authenticator app.

**Removing someone:** delete their entry and apply. Their login goes when the service is provisioned, and their sign-in once no service or core list still names their email.

**A new password for someone:** `terraform apply -replace='module.service.random_password.agent["<name>"]'`.

**Seeing every database:** people who need all services' data are on core's platform list (`platform.<name>`), not here.
