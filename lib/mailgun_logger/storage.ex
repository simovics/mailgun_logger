defmodule MailgunLogger.Storage do
  @moduledoc "JSON message storage with interchangeable backends."

  @callback put(String.t(), binary()) :: :ok | {:error, term()}
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}

  def put_message(api_id, message) when is_binary(api_id) and is_map(message) do
    safely(fn ->
      with {:ok, json} <- Jason.encode(message) do
        backend().put(api_id, json)
      end
    end)
  end

  def put_message(_, _), do: {:error, :invalid_message}

  def get_message(%{api_id: api_id}), do: get_message(api_id)

  def get_message(api_id) when is_binary(api_id) do
    safely(fn ->
      with {:ok, json} <- backend().get(api_id),
           {:ok, message} <- Jason.decode(json) do
        if is_map(message), do: {:ok, message}, else: {:error, :invalid_message}
      end
    end)
  end

  def get_message(_), do: {:error, :invalid_id}

  defp backend do
    Application.get_env(:mailgun_logger, :storage_backend, MailgunLogger.Storage.S3)
  end

  defp safely(fun) do
    fun.()
  rescue
    _ -> {:error, :storage_exception}
  end
end
