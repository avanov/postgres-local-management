# postgres-local-management
Makefile to manage local Postgres instances (to avoid Docker)

Usage
-----

Define `POSTGRES_LOCAL_MANAGEMENT_DIR`. Usually it's a project-local directory that's not tracked by your version control system.

For instance:
```bash
# .local/ is specified in .gitignore
export POSTGRES_LOCAL_MANAGEMENT_DIR=$(MY_PROJECT_ROOT)/.local
```

You can include this Makefile into your project's Makefile like this:
```Makefile
include $(POSTGRES_LOCAL_MANAGEMENT_REPO)/Makefile
```

Other customizable env vars
---------------------------

| Env var                                | Default if unset |
|----------------------------------------|------------------|
| `POSTGRES_LOCAL_MANAGEMENT_DB_HOST`    | `localhost`      |
| `POSTGRES_LOCAL_MANAGEMENT_DB_PORT`    | `5432`           |
| `POSTGRES_LOCAL_MANAGEMENT_DB_USER`    | `$(USER)`        |
| `POSTGRES_LOCAL_MANAGEMENT_DB_NAME`    | `$(USER)`        |
| `POSTGRES_LOCAL_MANAGEMENT_DB_PASS`    | `$(USER)`        |
