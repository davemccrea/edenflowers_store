defmodule EdenflowersWeb.Marketing.ContactDrawerTest do
  use EdenflowersWeb.ConnCase, async: true
  use Oban.Testing, repo: Edenflowers.Repo

  import Phoenix.LiveViewTest

  alias Edenflowers.ContactMessage.SendEmails

  @message %{"name" => "Karin Holm", "email" => "karin@example.com", "message" => "A white heart, please."}

  for path <- ["/en/contact", "/en/condolences"] do
    test "a message sent from #{path} goes out with the sender's details", %{conn: conn} do
      {:ok, view, _html} = live(conn, unquote(path))

      view |> form("#contact-form", message: @message) |> render_submit()

      assert has_element?(view, "#contact-sent")

      assert_enqueued(
        worker: SendEmails,
        args: %{name: "Karin Holm", message: "A white heart, please.", locale: "en-GB"}
      )
    end
  end

  test "a message without one of the required fields isn't sent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/contact")

    view |> form("#contact-form", message: Map.delete(@message, "message")) |> render_submit()

    refute has_element?(view, "#contact-sent")
    refute_enqueued(worker: SendEmails)
  end

  test "a filled-in honeypot looks sent but nothing goes out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/contact")

    view |> form("#contact-form", message: @message) |> render_submit(%{message: %{website: "spam.example"}})

    assert has_element?(view, "#contact-sent")
    refute_enqueued(worker: SendEmails)
  end
end
