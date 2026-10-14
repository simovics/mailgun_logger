defmodule MailgunLoggerWeb.EventController do
  use MailgunLoggerWeb, :controller

  alias MailgunLogger.Events
  alias MailgunLogger.Accounts

  def index(conn, params) do
    accounts = Accounts.list_accounts()

    case Events.search_events(params) do
      {:ok, {events, meta}} ->
        render(conn, :index, meta: meta, events: events, accounts: accounts)

      {:error, %Flop.Meta{} = meta} ->
        conn
        |> put_flash(:error, "Something went wrong")
        |> put_status(500)
        |> render(:index, meta: meta, events: [], accounts: accounts)
    end
  end

  def show(conn, %{"id" => event_id}) do
    event = event_id |> Events.get_event() |> Events.preload(:account)
    render(conn, :show, event: event)
  end

  def stored_message(conn, %{"id" => event_id}) do
    case Events.get_event(event_id) do
      nil ->
        send_resp(conn, 404, "Event not found")

      %{has_stored_message: true} = event ->
        case Mailgun.Events.get_stored_message_content(event) do
          content when is_binary(content) ->
            conn
            |> put_layout(false)
            |> render(:stored_message, html: String.replace(content, "bgcolor", "_bgcolor"))

          {:error, :not_found} ->
            send_resp(conn, 404, "Archived message not found")

          {:error, _} ->
            send_resp(conn, 503, "Archived message is temporarily unavailable")
        end

      _event ->
        redirect(conn, to: Routes.event_path(conn, :index))
    end
  end
end
