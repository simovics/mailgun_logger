defmodule MailgunLogger.Storage.S3 do
  @moduledoc "S3 backend preserving the existing bucket and object-key configuration."
  @behaviour MailgunLogger.Storage

  @impl true
  def put(api_id, json) do
    case bucket() |> ExAws.S3.put_object(file_path(api_id), json) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(api_id) do
    case bucket() |> ExAws.S3.get_object(file_path(api_id)) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def file_path(%{api_id: api_id}), do: file_path(api_id)
  def file_path(api_id), do: Path.join(base_dir(), file_name(api_id))
  def file_name(api_id), do: "#{api_id}.json"
  def base_dir, do: Application.get_env(:ex_aws, :raw_path)
  def bucket, do: Application.get_env(:ex_aws, :bucket)
end
