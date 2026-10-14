defmodule MailgunLogger.Storage.Filesystem do
  @moduledoc "Private JSON files stored beneath ML_STORAGE_PATH."
  @behaviour MailgunLogger.Storage

  @impl true
  def put(api_id, json) do
    destination = path(api_id)
    directory = Path.dirname(destination)
    suffix = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    temporary = destination <> "." <> suffix <> ".tmp"

    with :ok <- File.mkdir_p(directory) do
      try do
        with {:ok, :ok} <-
               File.open(temporary, [:write, :binary, :exclusive], fn file ->
                 with :ok <- File.chmod(temporary, 0o600),
                      :ok <- IO.binwrite(file, json) do
                   :file.sync(file)
                 end
               end),
             :ok <- File.rename(temporary, destination) do
          :ok
        else
          {:ok, {:error, reason}} -> {:error, reason}
          {:error, reason} -> {:error, reason}
        end
      after
        File.rm(temporary)
      end
    end
  end

  @impl true
  def get(api_id) do
    case File.read(path(api_id)) do
      {:error, :enoent} -> {:error, :not_found}
      result -> result
    end
  end

  def path(api_id) when is_binary(api_id) do
    root = Application.fetch_env!(:mailgun_logger, :storage_path) |> Path.expand()
    hash = :crypto.hash(:sha256, api_id) |> Base.encode16(case: :lower)
    Path.join([root, String.slice(hash, 0, 2), String.slice(hash, 2, 2), hash <> ".json"])
  end
end
