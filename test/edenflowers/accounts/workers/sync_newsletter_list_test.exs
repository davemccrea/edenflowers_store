defmodule Edenflowers.Accounts.Workers.SyncNewsletterListTest do
  # Sets the list ID in the global app env.
  use Edenflowers.DataCase, async: false

  import Edenflowers.Actors

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Workers.SyncNewsletterList

  setup do
    Application.put_env(:edenflowers, :brevo_newsletter_list_id, "7")
    on_exit(fn -> Application.delete_env(:edenflowers, :brevo_newsletter_list_id) end)
  end

  test "adds new subscribers, updates listed ones, removes those who opted out" do
    {:ok, listed} = Accounts.subscribe_to_newsletter("listed@example.com", "fi", authorize?: false)
    {:ok, _} = Accounts.update_name(listed, "Aino Virtanen", actor: system_actor())
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
                       "attributes" => %{"FIRSTNAME" => "Aino", "LANGUAGE" => "fi"}
                     }}

    assert_received {:removed, %{"emails" => ["left@example.com"]}}
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
