defmodule Edenflowers.Orders.GiftVoucherSaleTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Workers.SendReceiptEmail
  alias Edenflowers.Payments
  alias Edenflowers.Payments.GiftVoucher
  alias Edenflowers.Payments.GiftVoucherPdf

  setup :verify_on_exit!

  defp start_sale(amount, attrs \\ %{}) do
    Orders.start_gift_voucher_sale!(
      amount,
      Map.merge(
        %{
          customer_name: "Anna Buyer",
          customer_email: "anna@example.com",
          recipient_name: "Mia",
          locale: "sv-FI",
          voucher_locale: "fi"
        },
        attrs
      ),
      actor: nil
    )
  end

  # Pays the sale through Stripe as the webhook would.
  defp buy(amount, attrs \\ %{}) do
    sale = start_sale(amount, attrs)
    id = sale.id
    cents = amount * 100

    expect(StripeAPI.Mock, :create_payment_intent, fn ^cents, %{"order_id" => ^id}, nil ->
      {:ok, %{id: "pi_#{id}", client_secret: "pi_secret", amount: cents}}
    end)

    assert {:ok, %{client_secret: "pi_secret"}} = Orders.prepare_checkout_payment(id, actor: nil)

    payment_intent = %{id: "pi_#{id}", status: "succeeded", metadata: %{"order_id" => id}, amount_received: cents}
    assert {:ok, :completed} = Payments.complete(payment_intent)

    Ash.load!(Orders.get_order_by_id!(id, authorize?: false), [:cancellable?, line_items: [:gift_voucher]],
      authorize?: false
    )
  end

  defp christmas_sale_details do
    %{
      customer_name: "A",
      customer_email: "a@example.com",
      recipient_name: "M",
      voucher_locale: "sv-FI",
      voucher_style: :christmas
    }
  end

  defp voucher(order) do
    [%{gift_voucher: voucher}] = order.line_items
    Ash.load!(voucher, [:remaining, :spendable?], authorize?: false, reuse_values?: false)
  end

  describe "buying a voucher" do
    test "placing the sale issues a voucher for its amount, outside VAT, handed over by email" do
      order = buy(50)

      refute Ash.load!(order, :refundable?, authorize?: false).refundable?,
             "its money goes back only by cancelling, which also stops the voucher"

      assert order.state == :placed
      assert order.fulfillment_status == :fulfilled
      assert order.vat_breakdown == []
      assert Decimal.eq?(voucher(order).remaining, 50)
      assert voucher(order).spendable?
    end

    test "the buyer is emailed the voucher's code with its card and their receipt" do
      order = buy(50)
      code = GiftVoucher.format_code(voucher(order).code)

      voucher = Ash.load!(voucher(order), [line_item: :order], authorize?: false)

      assert %{lang: "fi", labels: %{"gift-voucher" => "Lahjakortti"}} = GiftVoucherPdf.build_payload(voucher),
             "the card is in the language the buyer chose, not the one they shopped in"

      [job] = all_enqueued(worker: SendReceiptEmail)
      assert {:ok, _order} = perform_job(SendReceiptEmail, job.args)

      assert_email_sent(fn email ->
        assert email.text_body =~ code
        refute email.text_body =~ "collect"

        assert email.attachments |> Enum.map(& &1.filename) |> Enum.sort() ==
                 ["eden-flowers-#{order.order_reference}.pdf", "eden-flowers-gift-voucher-#{order.order_reference}.pdf"]
      end)
    end

    test "Jennie resends the voucher where the buyer asks, and the log says where it went" do
      order = buy(50)
      admin = generate(admin_user())

      assert {:ok, _order} =
               Orders.email_gift_voucher(order, %{to: "mia@example.com", subject: "Your voucher"}, actor: admin)

      assert_email_sent(fn email ->
        assert email.to == [{"", "mia@example.com"}]
        assert email.subject == "Your voucher"
        assert email.text_body =~ GiftVoucher.format_code(voucher(order).code)
        assert length(email.attachments) == 2
      end)

      versions = Ash.load!(order, :paper_trail_versions, authorize?: false).paper_trail_versions
      assert %{email_to: "mia@example.com"} = Enum.find(versions, &(&1.version_action_name == :email_gift_voucher))
    end

    test "a buyer collecting a gift card is told it's ready from the shop's next open day" do
      order = buy(30, %{collect_voucher_card: true, locale: "en-GB"})
      ready_on = Ash.load!(order, :voucher_card_ready_on, authorize?: false).voucher_card_ready_on
      calendar = Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)

      assert Date.after?(ready_on, Edenflowers.ShopTime.today(order.ordered_at))
      assert Edenflowers.Fulfillment.Availability.unavailable_reason(calendar, ready_on, order.ordered_at) == nil

      [job] = all_enqueued(worker: SendReceiptEmail)
      assert {:ok, _order} = perform_job(SendReceiptEmail, job.args)

      assert_email_sent(fn email ->
        assert email.text_body =~ "ready for you to collect"
        assert email.text_body =~ Calendar.strftime(ready_on, "%-d.%-m.%Y")
      end)
    end

    test "a gift card to collect keeps the order open until Jennie marks it collected" do
      order = buy(30, %{collect_voucher_card: true})

      assert order.fulfillment_status == :pending
      assert Ash.load!(order, :voucher_card_to_hand_over?, authorize?: false).voucher_card_to_hand_over?
    end

    test "amounts run from 20 to 200 € in steps of 10" do
      assert {:error, _} =
               Orders.start_gift_voucher_sale(25, %{
                 customer_name: "A",
                 customer_email: "a@example.com",
                 recipient_name: "M",
                 voucher_locale: "sv-FI"
               })

      assert {:error, _} =
               Orders.start_gift_voucher_sale(210, %{
                 customer_name: "A",
                 customer_email: "a@example.com",
                 recipient_name: "M",
                 voucher_locale: "sv-FI"
               })

      assert {:ok, _} =
               Orders.start_gift_voucher_sale(200, %{
                 customer_name: "A",
                 customer_email: "a@example.com",
                 recipient_name: "M",
                 voucher_locale: "sv-FI"
               })
    end

    test "the voucher prints in the style the buyer chose, cream unless they chose another" do
      cream = Ash.load!(voucher(buy(50)), [line_item: :order], authorize?: false)
      green = Ash.load!(voucher(buy(50, %{voucher_style: :green})), [line_item: :order], authorize?: false)

      assert %{style: :cream} = GiftVoucherPdf.build_payload(cream)
      assert %{style: :green} = GiftVoucherPdf.build_payload(green)
    end

    test "customers can choose the Christmas style only while Jennie offers it" do
      assert {:error, _} = Orders.start_gift_voucher_sale(50, christmas_sale_details(), actor: nil)

      calendar = Edenflowers.Fulfillment.get_shop_calendar!(authorize?: false)
      Edenflowers.Fulfillment.set_christmas_vouchers_online!(calendar, true, authorize?: false)

      assert {:ok, %{voucher_style: :christmas}} =
               Orders.start_gift_voucher_sale(50, christmas_sale_details(), actor: nil)
    end

    test "going back changes the amount on the same sale" do
      sale = start_sale(50)
      revised = Orders.revise_gift_voucher_sale!(sale, 80, %{}, actor: nil, load: [:grand_total, :line_items])

      assert Decimal.eq?(revised.grand_total, 80)
      assert length(revised.line_items) == 1
    end

    test "a voucher can't pay for another one" do
      sale = start_sale(50)
      %{code: code} = generate(gift_voucher())

      assert {:error, _} = Orders.add_gift_voucher_with_code(sale, code, actor: nil)
    end
  end

  describe "refunding a voucher" do
    setup do
      %{admin: generate(admin_user())}
    end

    test "cancelling an unspent voucher's sale refunds the card and stops the voucher", %{admin: admin} do
      order = buy(50)
      pi = "pi_#{order.id}"

      StripeAPI.Mock
      |> stub(:list_refunds, fn ^pi -> {:ok, []} end)
      |> expect(:create_refund, fn ^pi, 5000, _key, _metadata ->
        {:ok, %{id: "re_#{order.id}", payment_intent: pi, amount: 5000, status: "succeeded"}}
      end)

      assert order.cancellable?
      assert {:ok, _cancelled} = Orders.cancel_order(order, %{email_customer?: false}, actor: admin)
      refute voucher(order).spendable?
    end

    test "once any of it is spent, the sale can't be cancelled", %{admin: admin} do
      order = buy(50)
      spent_on = generate(order(state: :placed))
      generate(payment(order_id: spent_on.id, gift_voucher_id: voucher(order).id, method: :voucher))

      refute Ash.load!(order, :cancellable?, authorize?: false, reuse_values?: false).cancellable?
      assert {:error, _} = Orders.cancel_order(order, %{email_customer?: false}, actor: admin)
    end

    test "its money is handed back only by cancelling", %{admin: admin} do
      order = buy(50)

      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:refund, %{amount: "10.00", payment_method: :stripe, email_customer?: false},
                 actor: admin
               )
               |> Ash.update()

      assert Exception.message(error) =~ "Cancel the order"
    end
  end
end
