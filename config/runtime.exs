import Config

storage_backend =
  case System.get_env("ML_STORAGE_BACKEND", "s3") do
    "s3" -> MailgunLogger.Storage.S3
    "filesystem" -> MailgunLogger.Storage.Filesystem
    other -> raise ArgumentError, "Unsupported ML_STORAGE_BACKEND: #{inspect(other)}"
  end

config :mailgun_logger,
  store_messages: System.get_env("ML_STORE_MESSAGES", "false") |> String.downcase() == "true",
  storage_backend: storage_backend,
  storage_path: System.get_env("ML_STORAGE_PATH", "/data/messages")

config :mailgun_logger, MailgunLoggerWeb.Endpoint,
  server: true,
  secret_key_base: System.get_env("SECRET_KEY_BASE")

config :mailgun_logger, MailgunLogger.Repo,
  username: System.get_env("ML_DB_USER"),
  password: System.get_env("ML_DB_PASSWORD"),
  database: System.get_env("ML_DB_NAME"),
  hostname: System.get_env("ML_DB_HOST"),
  port: System.get_env("ML_DB_PORT") || 5432

config :mailgun_logger, MailgunLogger.Mailer,
  adapter: Bamboo.MailgunAdapter,
  api_key: System.get_env("MAILGUN_API_KEY"),
  domain: System.get_env("MAILGUN_DOMAIN"),
  from: System.get_env("MAILGUN_FROM") || "no-reply@jackjoe.be"

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: System.get_env("AWS_REGION"),
  bucket: System.get_env("AWS_BUCKET"),
  raw_path: System.get_env("RAW_PATH"),
  s3: [
    scheme: System.get_env("AWS_SCHEME"),
    port: System.get_env("AWS_PORT"),
    region: System.get_env("AWS_REGION"),
    host: System.get_env("AWS_HOST")
  ]
