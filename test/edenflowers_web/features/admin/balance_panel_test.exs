defmodule EdenflowersWeb.Admin.BalancePanelTest do
  @moduledoc """
  Every case in the loop runs on the order page's panel and on a courses page
  row, which settle a balance the same ways.
  """
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Mox
  import Phoenix.LiveViewTest

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

  defp open(conn, :order, order) do
    {:ok, view, _html} = live(conn, ~p"/admin/orders/#{order.id}")
    {view, "#order-balance"}
  end

  defp open(conn, :booking, registration) do
    {:ok, view, _html} = live(conn, ~p"/admin/courses")
    {view, "#registration-#{registration.id}"}
  end

  defp refund_form(:order, _record), do: "#order-balance-form"
  defp refund_form(:booking, registration), do: "#refund-#{registration.id}"

  defp balance(record), do: Ash.load!(record, :balance, authorize?: false, reuse_values?: false).balance

  for parent <- [:order, :booking] do
    describe "#{parent}" do
      @parent parent

      test "to refund after paying by card and cash offers both ways back", %{conn: conn} do
        record = build(@parent, cancelled: true, payments: [stripe: "58.50", cash: "30.00"])
        {view, panel} = open(conn, @parent, record)

        assert has_element?(view, panel, "To refund €88.50")
        assert has_element?(view, ~s|#{panel} button[phx-click="refund_with_stripe"]|, "Refund with Stripe")
        assert has_element?(view, ~s|#{refund_form(@parent, record)} input[name="payment[amount]"][value="-30.00"]|)
      end

      test "a settled one has nothing to settle", %{conn: conn} do
        record = build(@parent, payments: [cash: "88.50"])
        {view, panel} = open(conn, @parent, record)

        refute has_element?(view, panel, "To refund")
        refute has_element?(view, ~s|button[phx-click="refund_with_stripe"]|)
      end

      test "a cancelled one paid by card is refunded with Stripe from the panel", %{conn: conn} do
        record = build(@parent, cancelled: true, payments: [stripe: "88.50"])

        StripeAPI.Mock
        |> stub(:list_refunds, fn "pi_paid" -> {:ok, []} end)
        |> expect(:create_refund, fn "pi_paid", 8_850, _key ->
          {:ok, %{id: "re_#{record.id}", payment_intent: "pi_paid", amount: 8_850, status: "succeeded"}}
        end)

        {view, panel} = open(conn, @parent, record)

        assert has_element?(view, panel, "To refund €88.50")
        refute has_element?(view, refund_form(@parent, record))

        assert view |> element(~s|#{panel} button[phx-click="refund_with_stripe"]|) |> render_click() =~
                 "Refunded with Stripe."

        refute has_element?(view, panel, "To refund")
      end

      test "a cancelled one paid in cash is settled by the prefilled refund", %{conn: conn} do
        record = build(@parent, cancelled: true, payments: [cash: "88.50"])
        {view, panel} = open(conn, @parent, record)

        refute has_element?(view, ~s|#{panel} button[phx-click="refund_with_stripe"]|)
        view |> form(refund_form(@parent, record), payment: %{payment_method: "cash"}) |> render_submit()

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

  test "an order payment above the balance says why and records nothing", %{conn: conn} do
    order = build(:order)
    {view, panel} = open(conn, :order, order)

    assert view |> form("#{panel}-form", payment: %{amount: "100,00"}) |> render_submit() =~
             "That&#39;s more than is owed"

    assert Decimal.equal?(balance(order), "88.50")
  end

  # At the course it's one tap on the row, so the row stays one line.
  test "a booking to collect has the quick payment form and no panel", %{conn: conn} do
    registration = build(:booking)
    {:ok, view, _html} = live(conn, ~p"/admin/courses")

    refute has_element?(view, "#balance-#{registration.id}")
    assert has_element?(view, "#mark-paid-#{registration.id}")

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
