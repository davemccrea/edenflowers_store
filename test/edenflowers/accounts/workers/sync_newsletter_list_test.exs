defmodule Edenflowers.Accounts.Workers.SyncNewsletterListTest do
  # Run synchronously because one test clears the globally shared MailerLite API key.
  use Edenflowers.DataCase, async: false

  import Edenflowers.Actors
  import Generator

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Workers.PushNewsletterSubscriber
  alias Edenflowers.Accounts.Workers.SyncNewsletterList

  test "refreshes subscribers' fields and takes members the site hasn't opted in out of the Newsletter group" do
    {:ok, listed} = Accounts.subscribe_to_newsletter("Listed@Example.com", "fi", authorize?: false)
    {:ok, _} = Accounts.update_name(listed, "Aino Virtanen", actor: system_actor())

    generate(
      order(
        state: :placed,
        user_id: listed.id,
        customer_phone_number: "040 1234567",
        ordered_at: ~U[2026-03-01 10:00:00Z]
      )
    )

    generate(
      order(
        state: :placed,
        user_id: listed.id,
        customer_phone_number: "045 1505141",
        ordered_at: ~U[2026-05-02 10:00:00Z]
      )
    )

    {:ok, customer} = Accounts.upsert_user("customer@example.com", "Matti Meikäläinen", authorize?: false)
    generate(order(state: :placed, user_id: customer.id, ordered_at: DateTime.utc_now()))

    stub_mailerlite(members: [{"listed@example.com", "1"}, {"by-hand@example.com", "2"}], unsubscribed: [])

    assert :ok = perform_job(SyncNewsletterList, %{})

    assert_received {:upserted,
                     %{"email" => "listed@example.com", "fields" => fields, "groups" => [_newsletter]} = body}

    refute Map.has_key?(body, "status")

    assert fields == %{
             "name" => "Aino",
             "last_name" => "Virtanen",
             "phone" => "+358451505141",
             "language" => "fi",
             "order_count" => 2,
             "last_order_date" => "2026-05-02",
             "total_spent" => 0.0
           }

    assert_received {:removed_from_newsletter, "2"}
    refute_received {:upserted, %{"email" => "by-hand@example.com"}}
    refute_received {:upserted, %{"email" => "customer@example.com"}}
  end

  test "opts out users who unsubscribed in MailerLite" do
    {:ok, _} = Accounts.subscribe_to_newsletter("gone@example.com", "fi", authorize?: false)

    stub_mailerlite(members: [], unsubscribed: ["gone@example.com"])

    assert :ok = perform_job(SyncNewsletterList, %{})

    {:ok, user} = Accounts.get_user_by_email("gone@example.com", authorize?: false)
    refute user.newsletter_opt_in
    refute_received {:upserted, %{"email" => "gone@example.com", "fields" => _}}
  end

  test "an opt-in on the site resubscribes, an opt-out unsubscribes" do
    {:ok, user} = Accounts.subscribe_to_newsletter("back@example.com", "sv-FI", authorize?: false)
    stub_mailerlite(members: [], unsubscribed: [])

    assert :ok = perform_job(PushNewsletterSubscriber, %{"email" => "back@example.com"})

    assert_received {:upserted,
                     %{
                       "email" => "back@example.com",
                       "status" => "active",
                       "resubscribe" => true,
                       "groups" => [_newsletter],
                       "fields" => %{"language" => "sv-FI"}
                     }}

    {:ok, _} = Accounts.update_newsletter_preference(user, false, "sv-FI", actor: user)

    assert :ok = perform_job(PushNewsletterSubscriber, %{"email" => "back@example.com"})

    assert_received {:upserted, %{"email" => "back@example.com", "status" => "unsubscribed"} = body}
    refute Map.has_key?(body, "fields")
  end

  test "queues a push only when the opt-in changes" do
    {:ok, _} = Accounts.subscribe_to_newsletter("footer@example.com", "fi", authorize?: false)
    assert_enqueued worker: PushNewsletterSubscriber, args: %{"email" => "footer@example.com"}

    {:ok, user} = Accounts.upsert_user("toggle@example.com", "Aino", authorize?: false)
    {:ok, user} = Accounts.update_name(user, "Aino Virtanen", actor: user)
    {:ok, user} = Accounts.update_newsletter_preference(user, false, "fi", actor: user)
    refute_enqueued worker: PushNewsletterSubscriber, args: %{"email" => "toggle@example.com"}

    {:ok, _} = Accounts.update_newsletter_preference(user, true, "fi", actor: user)
    assert_enqueued worker: PushNewsletterSubscriber, args: %{"email" => "toggle@example.com"}
  end

  test "does nothing without an API key" do
    Application.delete_env(:edenflowers, :mailerlite_api_key)
    on_exit(fn -> Application.put_env(:edenflowers, :mailerlite_api_key, "test-mailerlite-key") end)

    assert :ok = perform_job(SyncNewsletterList, %{})
    assert :ok = perform_job(PushNewsletterSubscriber, %{"email" => "anyone@example.com"})
  end

  defp stub_mailerlite(members: members, unsubscribed: unsubscribed) do
    Req.Test.stub(Edenflowers.Accounts.MailerLite, fn
      %{method: "GET", path_info: ["api", "subscribers"]} = conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["filter"]["status"] == "unsubscribed"
        data = Enum.map(unsubscribed, &%{"email" => &1})
        Req.Test.json(conn, %{"data" => data, "meta" => %{"next_cursor" => nil}})

      %{method: "GET", path_info: ["api", "groups", _group, "subscribers"]} = conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.query_params["filter"]["status"] == "active"
        data = Enum.map(members, fn {email, id} -> %{"email" => email, "id" => id} end)
        Req.Test.json(conn, %{"data" => data, "meta" => %{"next_cursor" => nil}})

      %{method: "DELETE", path_info: ["api", "subscribers", id, "groups", _group]} = conn ->
        send(self(), {:removed_from_newsletter, id})
        conn |> Plug.Conn.put_status(204) |> Req.Test.text("")

      %{method: "POST", request_path: "/api/subscribers"} = conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(self(), {:upserted, Jason.decode!(body)})
        conn |> Plug.Conn.put_status(200) |> Req.Test.json(%{})
    end)
  end
end
