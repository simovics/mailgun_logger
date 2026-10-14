defmodule MailgunLogger.StorageTest do
  use ExUnit.Case, async: false

  alias MailgunLogger.Event
  alias MailgunLogger.Storage
  alias MailgunLogger.Storage.Filesystem

  setup do
    keys = [:storage_backend, :storage_path, :store_messages]
    previous = Enum.map(keys, &{&1, Application.fetch_env(:mailgun_logger, &1)})
    suffix = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    root = Path.join(System.tmp_dir!(), "mailgun-storage-" <> suffix)

    Application.put_env(:mailgun_logger, :storage_backend, Filesystem)
    Application.put_env(:mailgun_logger, :storage_path, root)
    Application.put_env(:mailgun_logger, :store_messages, true)

    on_exit(fn ->
      File.rm_rf!(root)

      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:mailgun_logger, key, value)
        {key, :error} -> Application.delete_env(:mailgun_logger, key)
      end)
    end)

    %{root: root}
  end

  test "round trips a JSON message" do
    message = %{"Content-Type" => "text/plain", "body-plain" => "Hello"}
    assert :ok = Storage.put_message("event-1", message)
    assert {:ok, ^message} = Storage.get_message("event-1")
    assert Mailgun.Events.get_stored_message_content(%{api_id: "event-1"}) == "Hello"
  end

  test "returns a controlled error for a missing file" do
    assert {:error, :not_found} = Storage.get_message("missing")
    assert {:error, :not_found} = Mailgun.Events.get_stored_message_content(%{api_id: "missing"})
  end

  test "returns a controlled error for corrupt JSON" do
    assert :ok = Filesystem.put("corrupt", "not json")
    assert {:error, _} = Storage.get_message("corrupt")
  end

  test "rejects JSON values that are not message objects" do
    assert :ok = Filesystem.put("array", "[]")
    assert {:error, :invalid_message} = Storage.get_message("array")
    assert {:error, :invalid_message} = Storage.put_message("error", {:error, :http_failure})
  end

  test "hashes external identifiers instead of using them as paths", %{root: root} do
    api_id = "../../outside/unsafe"
    path = Filesystem.path(api_id)
    relative = Path.relative_to(path, root)
    assert Regex.match?(~r/\A[0-9a-f]{2}\/[0-9a-f]{2}\/[0-9a-f]{64}\.json\z/, relative)
    assert :ok = Storage.put_message(api_id, %{"body-html" => "hello"})
    assert File.regular?(path)
  end

  test "replaces a message and leaves no temporary files", %{root: root} do
    assert :ok = Storage.put_message("replace", %{"value" => 1})
    assert :ok = Storage.put_message("replace", %{"value" => 2})
    assert {:ok, %{"value" => 2}} = Storage.get_message("replace")
    assert Path.wildcard(Path.join([root, "**", "*.tmp"])) == []
    assert {:ok, stat} = File.stat(Filesystem.path("replace"))
    assert Bitwise.band(stat.mode, 0o777) == 0o600
  end

  test "failed writes do not mark the event as archived", %{root: root} do
    File.write!(root, "this is a file, not a directory")
    event = %Event{api_id: "failure", has_stored_message: false}
    assert {:error, _} = Storage.put_message(event.api_id, %{"body-html" => "hello"})
    assert Mailgun.Events.archive_message(event, %{"body-html" => "hello"}) == event
  end

  test "disabled storage does not fetch, write, or mark a message", %{root: root} do
    Application.put_env(:mailgun_logger, :store_messages, false)

    event = %Event{
      api_id: "disabled",
      has_stored_message: false,
      raw: %{"storage" => %{"url" => "https://example.invalid/message"}}
    }

    assert Mailgun.Events.get_stored_message(nil, event) == event
    assert Mailgun.Events.archive_message(event, %{"body-html" => "hello"}) == event
    refute File.exists?(root)
  end
end
