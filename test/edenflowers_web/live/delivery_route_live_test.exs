defmodule EdenflowersWeb.DeliveryRouteLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Dispatch
  alias Edenflowers.HereTourPlanning.{Assignment, Plan, Stop}
  alias Edenflowers.Store.{DeliveryAttempt, DeliveryStop, Order}

  defp today, do: DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

  defp delivery_order(date) do
    generate(
      order(
        state: :placed,
        payment_status: :paid,
        fulfillment_status: :pending,
        fulfillment_method: :delivery,
        fulfillment_date: date,
        order_reference: "EF-#{System.unique_integer([:positive])}",
        recipient_name: "Anna Recipient",
        recipient_phone_number: "+358401234567",
        delivery_address: "Rauhankatu 5, 65100 Vaasa",
        delivery_instructions: "Ring the top buzzer",
        card_message: "Happy birthday!",
        position: "63.10,21.60"
      )
    )
  end

  defp publish_route(date) do
    order = delivery_order(date)
    driver = generate(driver(name: "Erik Driver", preferred_locale: "en-GB"))
    admin = generate(admin_user())

    plan = %Plan{
      assignments: [
        %Assignment{
          vehicle_id: driver.id,
          stops: [%Stop{order_id: order.id, sequence: 1, leg_distance: 3000, leg_duration: 600}],
          total_distance: 3000,
          total_driving_duration: 600,
          total_service_duration: 300
        }
      ]
    }

    {:ok, result} = Dispatch.publish(plan, %{delivery_date: date, published_by_user_id: admin.id})
    entry = hd(result.routes)
    stop = DeliveryStop |> Ash.read!(authorize?: false) |> hd()
    %{token: entry.raw_token, route_id: entry.route.id, order: order, stop: stop}
  end

  test "invalid token renders an error", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/deliveries/totally-bogus-token")
    assert html =~ "not valid"
  end

  test "renders the ordered route with driver details and a Google Maps link", %{conn: conn} do
    %{token: token, order: order} = publish_route(today())

    {:ok, _view, html} = live(conn, ~p"/deliveries/#{token}")

    assert html =~ "Erik Driver"
    assert html =~ order.order_reference
    assert html =~ "Anna Recipient"
    assert html =~ "tel:+358401234567"
    assert html =~ "Rauhankatu 5"
    assert html =~ "Ring the top buzzer"
    assert html =~ "Happy birthday!"
    assert html =~ "google.com/maps/dir/"
    assert html =~ "destination="
    # No prices are shown on the driver page.
    refute html =~ "€"
  end

  test "recording a delivered outcome fulfils the order and completes the route", %{conn: conn} do
    %{token: token, order: order, stop: stop} = publish_route(today())

    {:ok, view, _html} = live(conn, ~p"/deliveries/#{token}")

    view |> element("button[phx-value-stop-id='#{stop.id}']") |> render_click()

    view
    |> form("form[phx-submit=record_outcome]", %{
      outcome: "delivered",
      delivered_method: "handed_to_recipient"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Delivered"
    assert html =~ "Route complete"

    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :fulfilled
  end

  test "a failed attempt keeps the order pending and shows on retry", %{conn: conn} do
    %{token: token, order: order, stop: stop} = publish_route(today())

    {:ok, view, _html} = live(conn, ~p"/deliveries/#{token}")

    view |> element("button[phx-value-stop-id='#{stop.id}']") |> render_click()

    # Switching to "failed" reveals the reason select.
    view |> form("form[phx-submit=record_outcome]", %{outcome: "failed"}) |> render_change()

    view
    |> form("form[phx-submit=record_outcome]", %{
      outcome: "failed",
      failure_reason: "recipient_unavailable"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Last attempt failed"
    refute html =~ "Route complete"
    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :pending

    # Retry succeeds.
    view |> element("button[phx-value-stop-id='#{stop.id}']") |> render_click()

    view
    |> form("form[phx-submit=record_outcome]", %{outcome: "delivered", delivered_method: "handed_to_recipient"})
    |> render_submit()

    assert render(view) =~ "Route complete"
  end

  test "records a delivered outcome with a proof photo written to disk", %{conn: conn} do
    %{token: token, stop: stop} = publish_route(today())

    {:ok, view, _html} = live(conn, ~p"/deliveries/#{token}")

    view |> element("button[phx-value-stop-id='#{stop.id}']") |> render_click()

    photo =
      file_input(view, "form[phx-submit=record_outcome]", :photo, [
        %{name: "proof.jpg", content: "FAKEJPEGBYTES", type: "image/jpeg"}
      ])

    render_upload(photo, "proof.jpg")

    view
    |> form("form[phx-submit=record_outcome]", %{outcome: "delivered", delivered_method: "handed_to_recipient"})
    |> render_submit()

    attempt = DeliveryAttempt |> Ash.read!(authorize?: false) |> hd()
    assert attempt.photo_path
    assert attempt.photo_media_type == "image/jpeg"
    assert attempt.photo_original_filename == "proof.jpg"

    root = Application.fetch_env!(:edenflowers, :proof_photo_root)
    assert File.exists?(Path.join(root, attempt.photo_path))
  end

  test "an expired route is read-only with no record action", %{conn: conn} do
    yesterday = Date.add(today(), -1)
    %{token: token} = publish_route(yesterday)

    {:ok, view, html} = live(conn, ~p"/deliveries/#{token}")

    assert html =~ "expired"
    refute has_element?(view, "button[phx-click=open_outcome]")
  end
end
