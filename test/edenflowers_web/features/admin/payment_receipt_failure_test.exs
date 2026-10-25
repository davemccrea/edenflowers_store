defmodule EdenflowersWeb.Admin.PaymentReceiptFailureTest do
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  @moduletag capture_log: true

  defmodule FailingAdapter do
    use Swoosh.Adapter

    @impl true
    def deliver(_email, _config), do: {:error, :unavailable}
  end

  setup :log_in_admin

  test "a committed part payment closes and clears the form even when its receipt fails", %{conn: conn} do
    config = Application.fetch_env!(:edenflowers, Edenflowers.Mailer)
    Application.put_env(:edenflowers, Edenflowers.Mailer, adapter: FailingAdapter)
    on_exit(fn -> Application.put_env(:edenflowers, Edenflowers.Mailer, config) end)

    order = placed_order(payment_intent_id: nil)
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    view |> element("#order-balance-settle") |> render_click()

    html =
      view
      |> form("#order-balance-form", payment: %{amount: "20.00", payment_method: "cash", email_receipt: "true"})
      |> render_submit()

    assert html =~ "Payment recorded, but the receipt could not be emailed."
    assert_push_event(view, "js-exec", %{to: "#settlement-drawer", attr: "phx-hide"})
    refute has_element?(view, "#settlement-drawer [role=alert]")

    order = Ash.load!(order, [:balance, :payments], authorize?: false, reuse_values?: false)
    assert [%{method: :cash, amount: amount}] = order.payments
    assert Decimal.equal?(amount, "20.00")
    assert Decimal.equal?(order.balance, "68.50")

    view |> element("#order-balance-settle") |> render_click()
    assert has_element?(view, ~s|input[name="payment[amount]"][value="68.50"]|)
    assert_no_email_sent()
  end
end
