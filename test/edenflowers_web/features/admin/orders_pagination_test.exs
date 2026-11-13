defmodule EdenflowersWeb.Admin.OrdersPaginationTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  setup :log_in_admin

  test "renders rows before counting, then supplies totals and the next page", %{conn: conn} do
    previous = Application.get_env(:ash, :disable_async?)
    Application.put_env(:ash, :disable_async?, false)
    on_exit(fn -> Application.put_env(:ash, :disable_async?, previous) end)

    today = Edenflowers.ShopTime.today()

    orders =
      for i <- 1..26 do
        generate(
          order(
            state: :placed,
            customer_name: "Customer #{i}",
            fulfillment_date: Date.add(today, i),
            fulfillment_status: :pending
          )
        )
      end

    ref = make_ref()

    :ok =
      :telemetry.attach(
        ref,
        [:edenflowers, :repo, :query],
        fn _event, _measurements, metadata, owner ->
          if metadata.source == "orders" and String.starts_with?(metadata.query, "SELECT coalesce(count(*),") do
            send(owner, {ref, self()})
          end
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(ref) end)

    conn = get(conn, ~p"/admin/orders")
    assert html_response(conn, 200) =~ "Customer 1"
    refute_received {^ref, _pid}

    {:ok, view, _html} = live(conn)
    render_async(view)

    assert_received {^ref, count_pid}
    assert count_pid != view.pid
    assert has_element?(view, ~s([data-key="pagination_info_class"]), "showing 1-25 of 26")

    view |> element(~s(button[title="Next page"])) |> render_click()
    render_async(view)

    assert has_element?(view, ~s([data-item-id="#{List.last(orders).id}"]))
    refute has_element?(view, ~s([data-item-id="#{hd(orders).id}"]))
    assert has_element?(view, ~s([data-key="pagination_info_class"]), "showing 26-26 of 26")
  end
end
