defmodule EdenflowersWeb.Admin.BalancePanelTest do
  @moduledoc """
  Every case in the loop runs on the order page's panel and on a courses page
  row, which settle a balance the same ways.
  """
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.External.StripeAPI

  setup :verify_on_exit!

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
  end

  # An order or booking for 88.50, paid with `payments` like `[stripe: "58.50", cash: "30.00"]`.
  defp build(parent, opts \\ []) do
    cancelled? = Keyword.get(opts, :cancelled, false)

    record =
      case parent do
        :order ->
          placed_order(payment_intent_id: nil, fulfillment_status: if(cancelled?, do: :cancelled, else: :pending))

        :booking ->
          generate(
            course_registration(status: if(cancelled?, do: :cancelled, else: :confirmed), amount: Decimal.new("88.50"))
          )
      end

    for {method, amount} <- Keyword.get(opts, :payments, []) do
      payment_intent_id = if method == :stripe, do: "pi_paid"

      generate(
        payment([
          {parent_key(parent), record.id},
          method: method,
          amount: Decimal.new(amount),
          payment_intent_id: payment_intent_id
        ])
      )
    end

    record
  end

  defp parent_key(:order), do: :order_id
  defp parent_key(:booking), do: :course_registration_id

  # Both pages settle a balance in the drawer the balance's button opens.
  defp open(conn, :order, order) do
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    if has_element?(view, "#order-balance-settle"), do: view |> element("#order-balance-settle") |> render_click()
    {view, "#order-balance"}
  end

  defp open(conn, :booking, registration) do
    {:ok, view, _html} = live(conn, ~p"/admin/courses")
    settle = "#settle-#{registration.id}"
    if has_element?(view, settle), do: view |> element(settle) |> render_click()
    {view, "#registration-#{registration.id}"}
  end

  defp stripe_refund_button(:order, _order), do: ~s|#settlement-drawer button[phx-click="refund_with_stripe"]|
  defp stripe_refund_button(:booking, registration), do: ~s|#refund-#{registration.id} button[value="stripe"]|

  # The order's refund is a minus payment; a booking's is the amount handed back.
  defp prefilled_refund(:order, _order, amount),
    do: ~s|#order-balance-form input[name="payment[amount]"][value="-#{amount}"]|

  defp prefilled_refund(:booking, registration, amount),
    do: ~s|#refund-#{registration.id} input[name="refund[amount]"][value="#{amount}"]|

  defp record_refund_button(:order, _order), do: "#order-balance-form button[type=submit]"
  defp record_refund_button(:booking, registration), do: ~s|#refund-#{registration.id} button[value="record"]|

  defp refund_with_stripe(view, :order, order),
    do: view |> element(stripe_refund_button(:order, order)) |> render_click()

  defp refund_with_stripe(view, :booking, registration) do
    view
    |> form("#refund-#{registration.id}")
    |> put_submitter(stripe_refund_button(:booking, registration))
    |> render_submit()
  end

  defp record_cash_refund(view, :order, _order),
    do: view |> form("#order-balance-form", payment: %{payment_method: "cash"}) |> render_submit()

  defp record_cash_refund(view, :booking, registration) do
    view
    |> form("#refund-#{registration.id}", refund: %{payment_method: "cash"})
    |> put_submitter(record_refund_button(:booking, registration))
    |> render_submit()
  end

  defp balance(record), do: Ash.load!(record, :balance, authorize?: false, reuse_values?: false).balance

  defp receipt_checkbox(:order, _order), do: ~s|#order-balance-email-receipt[checked]|

  defp receipt_checkbox(:booking, registration),
    do: ~s|#mark-paid-#{registration.id} input[type=checkbox][name=email_receipt][checked]|

  defp record_cash_payment(view, :order, _order, email_receipt),
    do:
      view
      |> form("#order-balance-form", payment: %{payment_method: "cash", email_receipt: email_receipt})
      |> render_submit()

  defp record_cash_payment(view, :booking, registration, email_receipt) do
    view
    |> form("#mark-paid-#{registration.id}", payment_method: "cash", email_receipt: email_receipt)
    |> render_submit()
  end

  for parent <- [:order, :booking] do
    describe "#{parent}" do
      @parent parent

      test "to refund after paying by card and cash offers both ways back", %{conn: conn} do
        record = build(@parent, cancelled: true, payments: [stripe: "58.50", cash: "30.00"])
        {view, panel} = open(conn, @parent, record)

        assert has_element?(view, panel, "To refund €88.50")
        assert has_element?(view, stripe_refund_button(@parent, record), "Refund with Stripe")
        assert has_element?(view, record_refund_button(@parent, record))
      end

      test "the payment that settles it emails a receipt, ticked by default", %{conn: conn} do
        record = build(@parent)
        {view, _panel} = open(conn, @parent, record)

        assert has_element?(view, receipt_checkbox(@parent, record))
        assert record_cash_payment(view, @parent, record, "true") =~ "Payment recorded and receipt emailed."

        assert Decimal.eq?(balance(record), 0)
        assert_email_sent(fn email -> assert [%{content_type: "application/pdf"}] = email.attachments end)
      end

      test "unticked, the payment that settles it sends nothing", %{conn: conn} do
        record = build(@parent)
        {view, _panel} = open(conn, @parent, record)

        assert record_cash_payment(view, @parent, record, "false") =~ "Payment recorded."

        assert Decimal.eq?(balance(record), 0)
        assert_no_email_sent()
      end

      test "a settled one has nothing to settle", %{conn: conn} do
        record = build(@parent, payments: [cash: "88.50"])
        {view, panel} = open(conn, @parent, record)

        refute has_element?(view, panel, "To refund")
        refute has_element?(view, stripe_refund_button(@parent, record))
      end

      test "a cancelled one paid by card is refunded with Stripe from the panel", %{conn: conn} do
        record = build(@parent, cancelled: true, payments: [stripe: "88.50"])

        StripeAPI.Mock
        |> stub(:list_refunds, fn "pi_paid" -> {:ok, []} end)
        |> expect(:create_refund, fn "pi_paid", 8_850, _key, _metadata ->
          {:ok, %{id: "re_#{record.id}", payment_intent: "pi_paid", amount: 8_850, status: "succeeded"}}
        end)

        {view, panel} = open(conn, @parent, record)

        assert has_element?(view, panel, "To refund €88.50")
        refute has_element?(view, record_refund_button(@parent, record))
        assert refund_with_stripe(view, @parent, record) =~ "Refunded with Stripe."

        refute has_element?(view, panel, "To refund")
      end

      test "a cancelled one paid in cash is settled by the prefilled refund", %{conn: conn} do
        record = build(@parent, cancelled: true, payments: [cash: "88.50"])
        {view, panel} = open(conn, @parent, record)

        refute has_element?(view, stripe_refund_button(@parent, record))
        assert has_element?(view, prefilled_refund(@parent, record, "88.50"))
        record_cash_refund(view, @parent, record)

        refute has_element?(view, panel, "To refund")
        assert Decimal.eq?(balance(record), 0)
      end

      test "a payment recorded by mistake is undone, once", %{conn: conn} do
        record = build(@parent, payments: [cash: "88.50"])
        [payment] = Ash.load!(record, :payments, authorize?: false).payments
        {view, _panel} = open(conn, @parent, record)

        assert view |> element(undo_button(@parent, payment)) |> render_click() =~ "Payment undone."

        assert Decimal.equal?(balance(record), "88.50")
        refute has_element?(view, undo_button(@parent, payment))
      end

      test "a Stripe payment has no undo", %{conn: conn} do
        record = build(@parent, payments: [stripe: "88.50"])
        {view, _panel} = open(conn, @parent, record)

        refute has_element?(view, ~s|button[phx-click="undo_payment"]|)
      end
    end
  end

  defp undo_button(:order, payment),
    do: ~s|#order-payments button[phx-click="undo_payment"][phx-value-id="#{payment.id}"]|

  defp undo_button(:booking, payment), do: "#undo-payment-#{payment.id}"

  test "an order to collect shows the amount and a payment form prefilled with it", %{conn: conn} do
    order = build(:order)
    {view, panel} = open(conn, :order, order)

    assert has_element?(view, panel, "To collect €88.50")
    assert has_element?(view, ~s|#{panel}-form input[name="payment[amount]"][value="88.50"]|)

    view |> form("#{panel}-form", payment: %{payment_method: "cash"}) |> render_submit()

    refute has_element?(view, panel)
    assert Decimal.eq?(balance(order), 0)
  end

  test "an order refund above what's owed back says why and records nothing", %{conn: conn} do
    order = build(:order, cancelled: true, payments: [cash: "88.50"])
    {view, _panel} = open(conn, :order, order)

    assert view |> form("#order-balance-form", payment: %{amount: "-100,00"}) |> render_submit() =~
             "That&#39;s more than is owed back"

    assert Decimal.equal?(balance(order), "-88.50")
  end

  test "an order part payment doesn't offer a receipt", %{conn: conn} do
    order = build(:order)
    {view, panel} = open(conn, :order, order)

    assert has_element?(view, receipt_checkbox(:order, order))
    view |> form("#{panel}-form", payment: %{amount: "50,00"}) |> render_change()
    refute has_element?(view, "#order-balance-email-receipt")

    view |> form("#{panel}-form", payment: %{amount: "50,00", payment_method: "cash"}) |> render_submit()

    assert Decimal.equal?(balance(order), "38.50")
    assert_no_email_sent()
  end

  test "an order payment above the balance says why and records nothing", %{conn: conn} do
    order = build(:order)
    {view, panel} = open(conn, :order, order)

    assert view |> form("#{panel}-form", payment: %{amount: "100,00"}) |> render_submit() =~
             "That&#39;s more than is owed"

    assert has_element?(view, "#settlement-drawer [role=alert]", "more than is owed")
    assert has_element?(view, ~s|#order-balance-form input[name="payment[amount]"][value="100,00"]|)
    assert Decimal.equal?(balance(order), "88.50")
  end

  test "a booking to collect is settled from the drawer, not a panel on its row", %{conn: conn} do
    registration = build(:booking)
    {view, _panel} = open(conn, :booking, registration)

    refute has_element?(view, "#balance-#{registration.id}")
    assert has_element?(view, "#settlement-drawer #mark-paid-#{registration.id}")

    view |> form("#mark-paid-#{registration.id}", payment_method: "cash") |> render_submit()

    assert Decimal.eq?(balance(registration), 0)
    refute has_element?(view, "#mark-paid-#{registration.id}")
  end

  test "the order page offers its payment link only while something is to collect", %{conn: conn} do
    order = build(:order, cancelled: true, payments: [cash: "88.50"])
    {view, _panel} = open(conn, :order, order)
    refute has_element?(view, ~s|button[phx-click="email_payment_link"]|)

    {view, panel} = open(conn, :order, build(:order))
    assert has_element?(view, ~s|#{panel} button[phx-click="email_payment_link"]|)
    assert has_element?(view, ~s|#{panel} button[phx-click="open_payment_link"]|)
  end
end
