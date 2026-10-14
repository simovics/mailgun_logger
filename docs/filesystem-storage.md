# Filesystem message storage

Store event records in PostgreSQL and archived Mailgun message responses as private JSON files on the same VPS. No object-storage service is required. Message archives are Mailgun response JSON, not necessarily RFC 822/MIME .eml files.

## Configuration

Set these variables on the application container:

```env
ML_STORE_MESSAGES=true
ML_STORAGE_BACKEND=filesystem
ML_STORAGE_PATH=/data/messages
```

ML_STORAGE_BACKEND defaults to s3 for compatibility. ML_STORE_MESSAGES still defaults to false. Unknown backend names fail at startup. With filesystem storage, AWS credentials, AWS_BUCKET and RAW_PATH are not used for message reads or writes. Existing S3 dependencies remain installed.

## Docker Compose fragment

Merge this into your existing application service; retain its image/build, database, networking, secrets and other environment settings:

```yaml
services:
  mailgun_logger:
    environment:
      ML_STORE_MESSAGES: "true"
      ML_STORAGE_BACKEND: filesystem
      ML_STORAGE_PATH: /data/messages
    volumes:
      - /srv/mailgun-logger/messages:/data/messages
```

Create the host directory before starting the container. Set its ownership to the actual application runtime UID/GID and restrict access, for example mode 0700. Do not assume the runtime UID from the Dockerfile: its base image can define a user. Only the trusted application user and administrators should be able to modify this directory or its parents. Do not publish it through a static-file server. A Docker named volume mounted at /data/messages is also supported.

The application hashes the exact API event ID using SHA-256 and writes files as <root>/<first-two-hash-characters>/<next-two>/<full-hash>.json. The ID itself is never used as a filesystem path. Files are chmod 0600 before writing message content; writes use an exclusive randomly named temporary file, file sync, then rename in the same directory. Ordinary read/write errors are returned rather than raised. This is not a guarantee against host power loss or a compromised local storage directory.

Only successful writes set the database archive flag. A database update failure after a successful file write can leave an unreferenced file. Failed writes are logged; this patch does not add a retry queue. Disabled message storage skips fetching and archiving message bodies. Existing archive flags are not automatically repaired.

Missing archives return HTTP 404 from the existing authenticated message-viewing endpoint. Other archive read/decoding errors return HTTP 503.

## Existing archives

Switching backends does not migrate existing messages and does not provide automatic fallback to S3. Before changing an existing deployment, copy each existing S3 JSON object to the filesystem path computed by MailgunLogger.Storage.Filesystem.path(api_id), using the exact event api_id. Preserve the JSON content, set private permissions, and verify readback before switching. Keep the old archive until migration has been verified.

No database migration is required. Existing S3 settings and object keys remain supported when ML_STORAGE_BACKEND=s3.

## Tests and deployment checks

Tests were authored but have not been executed by the assistant. Run in an Elixir 1.17-compatible development/test environment with dependencies installed and the test PostgreSQL configuration available:

```sh
mix format config/runtime.exs lib/mailgun/events.ex lib/mailgun_logger/storage.ex lib/mailgun_logger/storage/*.ex lib/mailgun_logger_web/controllers/event_controller.ex test/lib/mailgun_logger/storage_test.exs
mix test test/lib/mailgun_logger/storage_test.exs
mix test
```

The project test alias creates/migrates the test database. Unit tests cover round trips, missing/corrupt files, malformed messages, safe paths, replacement, private file mode, failed writes and disabled storage. Validate successful archive-flag persistence against PostgreSQL and authenticated HTTP error responses in an integration environment as well.

Before production, rebuild the application image, archive a real message, confirm it renders, recreate the application container and confirm it still renders. Check behavior with a missing archive and a non-writable archive directory.

Back up PostgreSQL and the message directory, keep a backup outside the VPS, and test restoration. A persistent volume is not a backup. Monitor free disk space and inodes. No archive retention or deletion job is introduced by this patch.
