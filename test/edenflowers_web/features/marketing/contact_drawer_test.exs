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

  test "a message queues the shop email and an acknowledgement that carries no typed text", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/contact")

    view |> form("#contact-form", message: @message) |> render_submit()

    assert_enqueued(worker: SendEmails, args: %{acknowledgement: true, email: "karin@example.com", locale: "en-GB"})

    [acknowledgement] = Enum.filter(all_enqueued(worker: SendEmails), & &1.args["acknowledgement"])
    assert Enum.sort(Map.keys(acknowledgement.args)) == ["acknowledgement", "email", "locale"]
  end

  test "a message without one of the required fields isn't sent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/contact")

    view |> form("#contact-form", message: Map.delete(@message, "message")) |> render_submit()

    refute has_element?(view, "#contact-sent")
    refute_enqueued(worker: SendEmails)
  end

  test "an over-long message isn't sent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/contact")

    html =
      view |> form("#contact-form", message: %{@message | "message" => String.duplicate("a", 5001)}) |> render_submit()

    assert html =~ "Should be at most 5000 characters"
    refute has_element?(view, "#contact-sent")
    refute_enqueued(worker: SendEmails)
  end

  test "a filled-in honeypot looks sent but nothing goes out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/contact")

    view |> form("#contact-form", message: @message) |> render_submit(%{message: %{website: "spam.example"}})

    assert has_element?(view, "#contact-sent")
    refute_enqueued(worker: SendEmails)
  end

  test "a visitor's sixth message within the hour queues nothing, while another visitor still gets through", %{
    conn: conn
  } do
    busy = %{conn | remote_ip: {10, 20, 0, 1}}

    for _ <- 1..5 do
      {:ok, view, _html} = live(busy, ~p"/en/contact")
      view |> form("#contact-form", message: @message) |> render_submit()
      assert has_element?(view, "#contact-sent")
    end

    {:ok, view, _html} = live(busy, ~p"/en/contact")
    view |> form("#contact-form", message: @message) |> render_submit()

    refute has_element?(view, "#contact-sent")
    assert has_element?(view, "#contact-rate-limited", "Too many requests")
    assert length(all_enqueued(worker: SendEmails)) == 10

    {:ok, view, _html} = live(%{conn | remote_ip: {10, 20, 0, 2}}, ~p"/en/contact")
    view |> form("#contact-form", message: @message) |> render_submit()
    assert has_element?(view, "#contact-sent")
  end
end
