defmodule Edenflowers.Accounts.Workers.SyncNewsletterListTest do
  # Sets the list ID in the global app env.
  use Edenflowers.DataCase, async: false

  import Edenflowers.Actors
  import Generator

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Workers.SyncNewsletterList

  setup do
    Application.put_env(:edenflowers, :brevo_newsletter_list_id, "7")
    on_exit(fn -> Application.delete_env(:edenflowers, :brevo_newsletter_list_id) end)
  end

  test "adds new subscribers, updates listed ones, removes those who opted out" do
    {:ok, listed} = Accounts.subscribe_to_newsletter("listed@example.com", "fi", authorize?: false)
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

    {:ok, _} = Accounts.subscribe_to_newsletter("New@Example.com", "sv-FI", authorize?: false)
    {:ok, _} = Accounts.upsert_user("left@example.com", "Left", authorize?: false)

    stub_brevo([%{"email" => "listed@example.com"}, %{"email" => "left@example.com"}])

    assert :ok = perform_job(SyncNewsletterList, %{})

    assert_received {:created,
                     %{
                       "email" => "new@example.com",
                       "attributes" => %{"LANGUAGE" => "sv-FI"},
                       "listIds" => [7],
                       "emailBlacklisted" => false
                     }}

    assert_received {:created,
                     %{
                       "email" => "listed@example.com",
                       "attributes" => %{
                         "FIRSTNAME" => "Aino",
                         "LASTNAME" => "Virtanen",
                         "LANGUAGE" => "fi",
                         "SMS" => "+358451505141",
                         "ORDER_COUNT" => 2,
                         "LAST_ORDER_DATE" => "2026-05-02"
                       }
                     }}

    assert_received {:removed, %{"emails" => ["left@example.com"]}}
  end

  test "keeps customers with a phone as contacts, off the list and blocklist untouched" do
    {:ok, customer} = Accounts.upsert_user("customer@example.com", "Matti Meikäläinen", authorize?: false)
    {:ok, _} = Accounts.upsert_user("emailonly@example.com", "Email Only", authorize?: false)

    generate(
      order(state: :placed, user_id: customer.id, customer_phone_number: "040 1234567", ordered_at: DateTime.utc_now())
    )

    stub_brevo([])

    assert :ok = perform_job(SyncNewsletterList, %{})

    assert_received {:created, %{"email" => "customer@example.com", "attributes" => %{"SMS" => "+358401234567"}} = body}
    refute Map.has_key?(body, "listIds")
    refute Map.has_key?(body, "emailBlacklisted")
    refute_received {:created, %{"email" => "emailonly@example.com"}}
  end

  test "leaves off an SMS number another contact already has" do
    {:ok, customer} = Accounts.upsert_user("shared@example.com", "Shared Phone", authorize?: false)

    generate(
      order(state: :placed, user_id: customer.id, customer_phone_number: "040 1234567", ordered_at: DateTime.utc_now())
    )

    Req.Test.stub(SyncNewsletterList, fn
      %{method: "GET"} = conn ->
        Req.Test.json(conn, %{"contacts" => []})

      %{method: "POST", request_path: "/v3/contacts"} = conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        body = Jason.decode!(body)
        send(self(), {:created, body})

        if Map.has_key?(body["attributes"], "SMS"),
          do: conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"code" => "duplicate_parameter"}),
          else: conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{})

      %{method: "POST"} = conn ->
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{})
    end)

    assert :ok = perform_job(SyncNewsletterList, %{})

    assert_received {:created, %{"attributes" => %{"SMS" => _}}}
    assert_received {:created, %{"email" => "shared@example.com", "attributes" => attributes}}
    refute Map.has_key?(attributes, "SMS")
  end

  test "opts out users who unsubscribed in Brevo" do
    {:ok, _} = Accounts.subscribe_to_newsletter("gone@example.com", "fi", authorize?: false)

    stub_brevo([%{"email" => "gone@example.com", "emailBlacklisted" => true}])

    assert :ok = perform_job(SyncNewsletterList, %{})

    {:ok, user} = Accounts.get_user_by_email("gone@example.com", authorize?: false)
    refute user.newsletter_opt_in
    assert_received {:removed, %{"emails" => ["gone@example.com"]}}
  end

  test "does nothing without a list ID" do
    Application.delete_env(:edenflowers, :brevo_newsletter_list_id)

    assert :ok = perform_job(SyncNewsletterList, %{})
  end

  defp stub_brevo(listed_contacts) do
    Req.Test.stub(SyncNewsletterList, fn
      %{method: "GET", request_path: "/v3/contacts/lists/7/contacts"} = conn ->
        Req.Test.json(conn, %{"contacts" => listed_contacts})

      %{method: "POST", request_path: "/v3/contacts"} = conn ->
        reply(conn, :created, 201)

      %{method: "POST", request_path: "/v3/contacts/lists/7/contacts/remove"} = conn ->
        reply(conn, :removed, 201)
    end)
  end

  defp reply(conn, tag, status) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    send(self(), {tag, Jason.decode!(body)})
    conn |> Plug.Conn.put_status(status) |> Req.Test.json(%{})
  end
end
