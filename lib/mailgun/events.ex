defmodule Mailgun.Events do
  @moduledoc """
  Interfacing the Mailgun API
  """

  alias Mailgun.Client
  alias MailgunLogger.Event
  alias MailgunLogger.Events
  alias MailgunLogger.Storage

  require Logger

  @chunk_size 10
  @chunk_timeout 25_000

  @doc """
  Get events.
  [api docs](https://documentation.mailgun.com/en/latest/api-events.html#events)
  """
  def get_events(%Client{} = client, opts \\ %{}) do
    Client.get(client, "/DOMAIN/events?" <> URI.encode_query(opts))
  end

  @doc "Retrieve the actual sent messages"
  def get_stored_messages(%Client{} = client, events) do
    events
    |> Enum.chunk_every(@chunk_size)
    |> Enum.map(fn chunk ->
      chunk
      |> Enum.map(&Task.async(fn -> get_stored_message(client, &1) end))
      |> Enum.map(&Task.await(&1, @chunk_timeout))
    end)
    |> List.flatten()
  end

  @doc "Retrieve and archive a message only when message storage is enabled."
  def get_stored_message(client, %Event{raw: raw} = event) do
    if Application.get_env(:mailgun_logger, :store_messages, false) do
      case get_in(raw || %{}, ["storage", "url"]) do
        nil ->
          event

        url ->
          message = Client.get(client, build_stored_message_url(client, url))
          archive_message(event, message)
      end
    else
      event
    end
  end

  @doc false
  def archive_message(%Event{} = event, message) do
    if Application.get_env(:mailgun_logger, :store_messages, false) do
      case Storage.put_message(event.api_id, message) do
        :ok ->
          case Events.has_stored_message(event) do
            {:ok, updated} ->
              updated

            {:error, _} ->
              Logger.error("Message archived but event flag update failed for event #{event.id}")
              event
          end

        {:error, _} ->
          Logger.error("Failed to archive message for event #{event.id}")
          event
      end
    else
      event
    end
  end

  @doc "Return the archived message map, or an error tuple if unavailable."
  def get_stored_message(event) do
    case Storage.get_message(event) do
      {:ok, message} -> message
      {:error, _} = error -> error
    end
  end

  def get_stored_message_content(event) do
    case get_stored_message(event) do
      {:error, _} = error ->
        error

      message when is_map(message) ->
        content_type = Map.get(message, "Content-Type", "")

        if is_binary(content_type) do
          field = if String.contains?(content_type, "text/plain"), do: "body-plain", else: "body-html"
          content = Map.get(message, field, "")
          if is_binary(content), do: content, else: {:error, :invalid_message}
        else
          {:error, :invalid_message}
        end
    end
  end

  # Preserve the existing public helpers for S3 object keys.
  defdelegate file_path(event_or_id), to: MailgunLogger.Storage.S3
  defdelegate file_name(api_id), to: MailgunLogger.Storage.S3
  defdelegate base_dir(), to: MailgunLogger.Storage.S3
  defdelegate bucket(), to: MailgunLogger.Storage.S3

  defp build_stored_message_url(client, "https://" <> r), do: "https://api:#{client.api_key}@#{r}"
  defp build_stored_message_url(_, url), do: url
end
