defmodule Edenflowers.Payments.OrderInvoiceTest do
  use Edenflowers.DataCase, async: true
  import Generator

  alias Edenflowers.Orders
  alias Edenflowers.Payments

  setup do
    standard = generate(tax_rate(percentage: "0.255"))
    reduced = generate(tax_rate(percentage: "0.14"))
    pickup = generate(fulfillment_option(tax_rate_id: standard.id, fulfillment_method: :pickup, base_price: "0.00"))
    %{admin: generate(admin_user()), standard: standard, reduced: reduced, pickup: pickup}
  end

  defp line(name, price, tax_rate, quantity \\ "1") do
    %{
      "kind" => "custom",
      "product_name" => name,
      "unit_price" => price,
      "tax_rate_id" => tax_rate.id,
      "quantity" => quantity
    }
  end

  # 2 × 40,00 at 25,5 % + 20,00 at 14 % + an 8,00 pickup fee at 25,5 %: 108,00.
  defp place(ctx, overrides \\ %{}) do
    params =
      Map.merge(
        %{
          customer_name: "Kukka Oy",
          customer_email: "office@kukka.fi",
          locale: "fi",
          payment_terms: :invoice,
          email_customer?: false,
          fulfillment_option_id: ctx.pickup.id,
          fulfillment_date: Date.add(Edenflowers.ShopTime.today(), 1),
          fulfillment_fee_override: "8.00",
          line_items: [line("Office bouquet", "40,00", ctx.standard, "2"), line("Chocolates", "20,00", ctx.reduced)]
        },
        overrides
      )

    {:ok, order} = Orders.place_custom_order(params, actor: ctx.admin)
    order
  end

  defp reload(order),
    do:
      Ash.load!(order, [:balance, :invoiced?, :invoiceable?, :payment_status], authorize?: false, reuse_values?: false)

  defp draft(order, admin) do
    {:ok, draft} = Payments.create_invoice_for_order(order.id, actor: admin)
    draft
  end

  defp issue(order, admin), do: Payments.issue_invoice(draft(order, admin), actor: admin)

  defp lines(invoice),
    do:
      Enum.map(
        invoice.lines,
        &{&1.description, Decimal.to_string(&1.quantity), Decimal.to_string(&1.unit_price),
         Decimal.to_string(&1.vat_rate)}
      )

  test "a draft for an order takes its buyer, lines, fee, date and number", ctx do
    order = place(ctx)
    {:ok, draft} = Payments.create_invoice_for_order(order.id, actor: ctx.admin)

    assert draft.order_id == order.id
    # Creating a draft must not add a send-history entry, which would imply it had been emailed.
    assert Ash.load!(draft, :paper_trail_versions, authorize?: false).paper_trail_versions == []
    assert draft.buyer_name == "Kukka Oy"
    assert to_string(draft.buyer_email) == "office@kukka.fi"
    assert draft.locale == "fi"
    assert draft.supply_date == order.fulfillment_date
    assert draft.supply_description =~ order.order_reference

    assert [
             {"Office bouquet", "2", "40.00", "25.5"},
             {"Chocolates", "1", "20.00", "14"},
             {_pickup_fee, "1", "8.00", "25.5"}
           ] = lines(draft)
  end

  test "a draft for an order takes the company details from the email's latest invoice, keeping the order's buyer",
       ctx do
    {:ok, earlier} =
      Payments.create_invoice(
        %{
          buyer_name: "Someone Else",
          buyer_email: "OFFICE@kukka.fi",
          business_customer: true,
          company_name: "Kukka Oy Ab",
          business_id: "2944459-6",
          billing_address: "Kauppakatu 1, Vaasa",
          customer_reference: "PO 7",
          locale: "en-GB",
          supply_date: ~D[2026-11-02],
          lines: [%{description: "Flowers", quantity: "1", unit_price: "10", vat_rate: "25.5"}]
        },
        actor: ctx.admin
      )

    {:ok, _} = Payments.issue_invoice(earlier, actor: ctx.admin)
    {:ok, draft} = Payments.create_invoice_for_order(place(ctx).id, actor: ctx.admin)

    assert {draft.buyer_name, draft.locale} == {"Kukka Oy", "fi"}
    assert draft.business_customer
    assert {draft.company_name, to_string(draft.business_id)} == {"Kukka Oy Ab", "2944459-6"}
    assert draft.billing_address == "Kauppakatu 1, Vaasa"
    assert draft.customer_reference == nil
  end

  defp edit(order, ctx, changes) do
    Orders.edit_order(
      order,
      Map.merge(
        %{
          customer_name: "Kukka Oy",
          customer_email: "office@kukka.fi",
          fulfillment_option_id: ctx.pickup.id,
          fulfillment_date: order.fulfillment_date,
          fulfillment_fee_override: "8.00",
          line_items: [line("Office bouquet", "40,00", ctx.standard, "2"), line("Chocolates", "20,00", ctx.reduced)]
        },
        changes
      ),
      actor: ctx.admin
    )
  end

  defp refused(result) do
    assert {:error, error} = result
    assert Exception.message(error) =~ "Credit the invoice first"
  end

  test "issuing it leaves nothing to collect on the order and locks what it bills until credited", ctx do
    order = place(ctx)
    assert reload(order).invoiceable?

    {:ok, invoice} = issue(order, ctx.admin)
    assert Decimal.equal?(invoice.amount, "108.00")

    order = reload(order)
    assert Decimal.equal?(order.balance, 0)
    assert order.payment_status == :invoiced
    assert order.invoiced?
    refute order.invoiceable?

    refused(Orders.cancel_order(order, %{}, actor: ctx.admin))
    refused(edit(order, ctx, %{payment_terms: :payment_link}))
    refused(edit(order, ctx, %{fulfillment_date: Date.add(order.fulfillment_date, 1)}))
    refused(edit(order, ctx, %{fulfillment_fee_override: "10.00"}))
    refused(edit(order, ctx, %{line_items: [line("Office bouquet", "50,00", ctx.standard, "2")]}))
    # Same 108,00 in all, but 10,00 moves from 14 % to 25,5 %: the invoice's VAT would no longer be the order's.
    refused(
      edit(order, ctx, %{
        line_items: [line("Office bouquet", "45,00", ctx.standard, "2"), line("Chocolates", "10,00", ctx.reduced)]
      })
    )

    assert {:error, _} = Payments.create_invoice_for_order(order.id, actor: ctx.admin)

    # Renamed lines and new delivery details keep every amount, so the invoice still holds.
    assert {:ok, _order} =
             edit(order, ctx, %{
               delivery_instructions: "Reception, 2nd floor",
               customer_phone_number: "040 123 4567",
               line_items: [
                 line("Reception bouquet", "40,00", ctx.standard, "2"),
                 line("Pralines", "20,00", ctx.reduced)
               ]
             })

    order = reload(order)
    assert Decimal.equal?(order.balance, 0)
    assert order.invoiced?

    {:ok, _credit_note} = Payments.cancel_invoice(%{invoice_id: invoice.id}, actor: ctx.admin)
    order = reload(order)
    assert Decimal.equal?(order.balance, "108.00")
    assert order.payment_status == :pending
    assert order.invoiceable?
  end

  test "an order on other terms, part-paid or already invoiced can't be invoiced", ctx do
    link_order = place(ctx, %{payment_terms: :payment_link})
    refute reload(link_order).invoiceable?
    assert {:error, _} = Payments.create_invoice_for_order(link_order.id, actor: ctx.admin)

    part_paid = place(ctx)
    {:ok, _} = Orders.record_payment(part_paid, "10.00", :cash, actor: ctx.admin)
    refute reload(part_paid).invoiceable?
    assert {:error, _} = Payments.create_invoice_for_order(part_paid.id, actor: ctx.admin)

    order = place(ctx)
    first = draft(order, ctx.admin)
    second = draft(order, ctx.admin)
    assert {:ok, _} = Payments.issue_invoice(first, actor: ctx.admin)
    assert {:error, error} = Payments.issue_invoice(second, actor: ctx.admin)
    assert Exception.message(error) =~ "can't be invoiced now"
  end

  test "a linked invoice must come to exactly the order's balance, however its lines are worded", ctx do
    order = place(ctx)
    draft = draft(order, ctx.admin)

    for price <- ["108.01", "107.99"] do
      lines = [%{description: "Flowers", quantity: "1", unit_price: price, vat_rate: "25.5"}]
      {:ok, draft} = Payments.update_invoice_draft(draft, %{lines: lines}, actor: ctx.admin)
      assert {:error, error} = Payments.issue_invoice(draft, actor: ctx.admin)
      assert Exception.message(error) =~ "Make them match"
    end

    assert Decimal.equal?(reload(order).balance, "108.00")

    lines = [
      %{description: "Flowers for the office", quantity: "1", unit_price: "88.00", vat_rate: "25.5"},
      %{description: "Chocolates", quantity: "1", unit_price: "20.00", vat_rate: "14"}
    ]

    {:ok, draft} = Payments.update_invoice_draft(draft, %{lines: lines}, actor: ctx.admin)
    assert {:ok, _invoice} = Payments.issue_invoice(draft, actor: ctx.admin)
  end

  test "a draft left stale by an edit to the order can't be issued", ctx do
    order = place(ctx)
    stale = draft(order, ctx.admin)

    {:ok, _order} =
      Orders.edit_order(
        order,
        %{
          customer_name: "Kukka Oy",
          customer_email: "office@kukka.fi",
          fulfillment_option_id: ctx.pickup.id,
          fulfillment_date: order.fulfillment_date,
          line_items: [line("Office bouquet", "50,00", ctx.standard, "2"), line("Chocolates", "20,00", ctx.reduced)]
        },
        actor: ctx.admin
      )

    assert {:error, error} = Payments.issue_invoice(stale, actor: ctx.admin)
    assert Exception.message(error) =~ "Make them match"
  end

  test "a cancelled order is invoiced for its cancellation charge, split per VAT rate", ctx do
    order = place(ctx)
    {:ok, order} = Orders.cancel_order(order, %{cancellation_charge: "54.00", email_customer?: false}, actor: ctx.admin)

    {:ok, draft} = Payments.create_invoice_for_order(order.id, actor: ctx.admin)

    # Split the 54.00 cancellation charge in the original VAT proportions:
    # 88.00 of the 108.00 total was at 25.5%, and 20.00 was at 14%.
    assert [{charge, "1", "44.00", "25.5"}, {charge, "1", "10.00", "14"}] = lines(draft)
    assert charge =~ order.order_reference
  end

  test "money paid on a linked invoice is the invoice's, and owed at month end until it is", ctx do
    order = place(ctx)
    {:ok, invoice} = issue(order, ctx.admin)

    assert {:ok, [open]} = Payments.list_open_invoices(invoice.due_date, actor: ctx.admin)
    assert open.id == invoice.id

    {:ok, _} = Payments.record_invoice_payment(invoice, "108.00", actor: ctx.admin)
    order = Ash.load!(order, [:amount_paid, :balance], authorize?: false)
    assert Decimal.equal?(order.amount_paid, 0)
    assert Decimal.equal?(order.balance, 0)
  end
end
