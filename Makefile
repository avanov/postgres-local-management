# relies on presence of 'POSTGRES_LOCAL_MANAGEMENT_DIR' env var
PG_MANAGEMENT_WORK_DIR		:= $(POSTGRES_LOCAL_MANAGEMENT_DIR)/postgres
PG_LOCAL_DB_PATH			:= $(PG_MANAGEMENT_WORK_DIR)/pgdata
# points where a PID file of a running Postgres instance could be found
PG_PROCESS_PATH				:= $(PG_LOCAL_DB_PATH)/postmaster.pid
# we need a separate ssl-generated file to avoid re-triggering the command
# when key files are touched by external processes
PG_SSL_GENERATED      		:= $(POSTGRES_LOCAL_MANAGEMENT_DIR)/ssl_generated
# this is a marker we choose to use to indicate that users are created for the given cluster
PG_USERS_INIT_PATH    		:= $(POSTGRES_LOCAL_MANAGEMENT_DIR)/users_initialised
PG_DB_INSTALLED       		:= $(POSTGRES_LOCAL_MANAGEMENT_DIR)/db_initialised
PG_SSL_CERT_FILE      		:= $(POSTGRES_LOCAL_MANAGEMENT_DIR)/local_nonsecret_ssl.crt
PG_SSL_KEY_FILE       		:= $(POSTGRES_LOCAL_MANAGEMENT_DIR)/local_nonsecret_ssl.key
PF_DUMP_FILENAME			:= "pg_backup.custom"
PG_DB_DUMP_PATH				:= $(POSTGRES_LOCAL_MANAGEMENT_DIR)/$(PF_DUMP_FILENAME)

# Default postgres values
POSTGRES_HOST               := $(if $(POSTGRES_LOCAL_MANAGEMENT_DB_HOST),$(POSTGRES_LOCAL_MANAGEMENT_DB_HOST),localhost)
POSTGRES_PORT               := $(if $(POSTGRES_LOCAL_MANAGEMENT_DB_PORT),$(POSTGRES_LOCAL_MANAGEMENT_DB_PORT),5432)
POSTGRES_USER               := $(if $(POSTGRES_LOCAL_MANAGEMENT_DB_USER),$(POSTGRES_LOCAL_MANAGEMENT_DB_USER),$(USER))
POSTGRES_DB_NAME            := $(if $(POSTGRES_LOCAL_MANAGEMENT_DB_NAME),$(POSTGRES_LOCAL_MANAGEMENT_DB_NAME),$(USER))
POSTGRES_DB_PASSWORD		:= $(if $(POSTGRES_LOCAL_MANAGEMENT_DB_PASS),$(POSTGRES_LOCAL_MANAGEMENT_DB_PASS),$(USER))
# https://pgdash.io/blog/pgctl-tips-tricks.html
POSTGRES_DOMAIN_SOCKETS_DIR  = /tmp


$(PG_MANAGEMENT_WORK_DIR):
	install -d $(PG_MANAGEMENT_WORK_DIR)


# https://www.postgresql.org/docs/14/ssl-tcp.html#SSL-CERTIFICATE-CREATION
# Generates SSL keypair for SSL client verification
$(PG_SSL_GENERATED): $(PG_MANAGEMENT_WORK_DIR)
	openssl req							\
		-nodes -new -x509 -days 365000	\
		-subj "/CN=$(POSTGRES_HOST)"	\
		-keyout $(PG_SSL_KEY_FILE)		\
		-out $(PG_SSL_CERT_FILE)
	chmod 0600 $(PG_SSL_KEY_FILE)
	touch $(PG_SSL_GENERATED)


# local DB depends on the untrack dir, it creates a directory structure inside it
$(PG_DB_INSTALLED): $(PG_SSL_GENERATED)
	touch $(PG_DB_INSTALLED)
	pg_ctl initdb -D $(PG_LOCAL_DB_PATH) -o "--locale=$(LANG)"


# A running postgres instance will generate this PID file.
# -o command flags https://www.postgresql.org/docs/12/app-postgres.html
# because git doesn't save the full file permissions, we have to chmod keys here
$(PG_PROCESS_PATH): $(PG_DB_INSTALLED)
	pg_ctl start -D $(PG_LOCAL_DB_PATH) --wait --timeout=30	\
	--log=$(PG_LOCAL_DB_PATH)/logs.log -o					\
		"-p $(POSTGRES_PORT)								\
			-k /tmp											\
			-l												\
			--ssl_cert_file=$(PG_SSL_CERT_FILE)				\
			--ssl_key_file=$(PG_SSL_KEY_FILE)				\
		";
	tail --lines 20 $(PG_LOCAL_DB_PATH)/logs.log


# users can be created only when PG process exists (indicated by PID file)
$(PG_USERS_INIT_PATH): $(PG_PROCESS_PATH)
	createuser --superuser $(POSTGRES_USER) -h $(POSTGRES_HOST) -p $(POSTGRES_PORT) || true
	createdb   --owner     $(POSTGRES_USER) -h $(POSTGRES_HOST) -p $(POSTGRES_PORT) --encoding utf8 $(POSTGRES_DB_NAME) || true
	psql -U $(POSTGRES_USER) -p $(POSTGRES_PORT) -h $(POSTGRES_HOST) $(POSTGRES_DB_NAME) -c "CREATE EXTENSION IF NOT EXISTS intarray"
	# indicate that we've completed the task
	touch $(PG_USERS_INIT_PATH)


.PHONY: postgres-init
postgres-init: $(PG_USERS_INIT_PATH)
	pg_ctl status -D $(PG_LOCAL_DB_PATH)


.PHONY: postgres-stop
postgres-stop:
	@if ! [ -z "$(shell lsof -nti:$(POSTGRES_PORT))" ]; then pg_ctl stop -D $(PG_LOCAL_DB_PATH) -o "-p $(POSTGRES_PORT)"; fi;


.PHONY: postgres-purge
postgres-purge: postgres-stop
	rm -rf $(PG_MANAGEMENT_WORK_DIR)
	rm $(POSTGRES_LOCAL_MANAGEMENT_DIR)/users_initialised
	rm $(POSTGRES_LOCAL_MANAGEMENT_DIR)/db_initialised


.PHONY: postgres-shell
postgres-shell:
	psql -U $(POSTGRES_USER) -p $(POSTGRES_PORT) -h $(POSTGRES_HOST) $(POSTGRES_DB_NAME)


# we use connection string format below because there's no CLI flag alternative
# for specifying 'sslrootcert' setting
.PHONY: postgres-dump-local
postgres-dump-local:
	PGPASSWORD=$(POSTGRES_DB_PASSWORD)			\
	PGDATABASE=$(POSTGRES_DB_NAME)				\
		pg_dump									\
			--format custom						\
			--verbose							\
			"host=$(POSTGRES_HOST) 				\
			 port=$(POSTGRES_PORT) 				\
			 user=$(POSTGRES_USER) 				\
			 sslrootcert=$(PG_SSL_CERT_FILE)"	\
		> $(PG_DB_DUMP_PATH)


# we use connection string format below because there's no CLI flag alternative
# for specifying 'sslrootcert' setting
.PHONY: postgres-restore-local
postgres-restore-local: FILENAME ?= $(PG_DB_DUMP_PATH)
postgres-restore-local:
	PGPASSWORD=$(POSTGRES_DB_PASSWORD)			\
	PGDATABASE=$(POSTGRES_DB_NAME)				\
		pg_restore								\
			--single-transaction				\
			--format custom						\
			--verbose							\
			--no-owner							\
			--no-privileges						\
			--schema=public     				\
			-d "host=$(POSTGRES_HOST) 			\
				port=$(POSTGRES_PORT) 			\
			 	user=$(POSTGRES_USER) 			\
			 	sslrootcert=$(PG_SSL_CERT_FILE)"\
		$(FILENAME)
