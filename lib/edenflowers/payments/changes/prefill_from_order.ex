defmodule Edenflowers.Payments.Changes.PrefillFromOrder do
  @moduledoc """
  Fills a new draft from the `invoiceable?` order it bills, in the order's
  language: one line per order line at its own price and VAT rate, plus the
  fulfillment fee. A cancelled order bills its cancellation charge instead,
  one line per VAT rate in proportion to the order's VAT breakdown. When the
  order's email has been invoiced before, the latest such invoice gives the
  addresses and company details, so a regular business customer's are not
  typed again; the order keeps its own name, email and language.
  Issuing checks the order again (`IssueInvoice`), so this only refuses what
  could never be issued.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  require Ash.Query

  alias Edenflowers.Orders.Calculations.Vat
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Invoice

  @previous_fields [:business_customer, :company_name, :business_id, :billing_address]

  @impl true
  def change(changeset, _opts, _context) do
    with id when not is_nil(id) <- Ash.Changeset.get_attribute(changeset, :order_id),
         %Order{invoiceable?: true} = order <- load(id) do
      Ash.Changeset.change_attributes(changeset, Map.merge(previous_customer(order.customer_email), prefill(order)))
    else
      nil -> changeset
      _not_invoiceable -> Ash.Changeset.add_error(changeset, field: :order_id, message: not_invoiceable())
    end
  end

  defp load(id) do
    load = [:invoiceable?, :balance, :cancelled?, :fulfillment_fee, :line_items]

    case Ash.get(Order, id, authorize?: false, load: load) do
      {:ok, order} -> order
      _ -> nil
    end
  end

  defp previous_customer(nil), do: %{}

  defp previous_customer(email) do
    key = email |> to_string() |> String.downcase()

    latest =
      Invoice
      |> Ash.Query.for_read(:previous_customers, %{}, authorize?: false)
      |> Ash.Query.filter(buyer_email_key == ^key)
      |> Ash.Query.limit(1)
      |> Ash.read_one!()

    if latest, do: Map.take(latest, @previous_fields), else: %{}
  end

  defp not_invoiceable,
    do: ~t"Only an order on invoice terms with nothing paid and a balance to collect can be invoiced."

  defp prefill(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      %{
        buyer_name: order.customer_name,
        buyer_email: order.customer_email,
        locale: order.locale,
        supply_date: order.fulfillment_date,
        supply_description: dgettext("receipts", "Order #%{number}", number: order.order_reference),
        lines: lines(order)
      }
    end)
  end

  defp lines(%{cancelled?: true} = order) do
    description = dgettext("receipts", "Cancellation charge, order #%{number}", number: order.order_reference)

    order
    |> Vat.breakdown()
    |> split(order.balance)
    |> Enum.map(fn {rate, amount} -> line(description, 1, amount, rate) end)
  end

  defp lines(order) do
    items = Enum.map(order.line_items, &line(&1.product_name, &1.quantity, &1.unit_price, &1.tax_rate))
    items ++ fee_line(order)
  end

  defp fee_line(%{fulfillment_fee: fee} = order) when not is_nil(fee) do
    if Decimal.positive?(fee) do
      description =
        if order.fulfillment_method == :delivery,
          do: dgettext("receipts", "Delivery fee"),
          else: dgettext("receipts", "Pickup fee")

      [line(description, 1, fee, order.fulfillment_tax_rate)]
    else
      []
    end
  end

  defp fee_line(_order), do: []

  @doc """
  `amount` split over the VAT `rows` in proportion to each row's gross,
  rounded to cents, the rounding left on the largest row so the parts add up.
  """
  def split(rows, amount) do
    total = Enum.reduce(rows, Decimal.new(0), &Decimal.add(&1.gross, &2))
    largest = Enum.max_by(rows, & &1.gross, Decimal)

    shares = Enum.map(rows, &{&1, amount |> Decimal.mult(&1.gross) |> Decimal.div(total) |> Decimal.round(2)})
    residual = Enum.reduce(shares, amount, fn {_row, share}, left -> Decimal.sub(left, share) end)

    for {row, share} <- shares,
        share = if(row == largest, do: Decimal.add(share, residual), else: share),
        not Decimal.eq?(share, 0),
        do: {row.rate, share}
  end

  defp line(description, quantity, unit_price, tax_rate) do
    %{
      description: description,
      quantity: Decimal.new(quantity),
      unit_price: unit_price,
      vat_rate: tax_rate |> Decimal.mult(100) |> Decimal.normalize()
    }
  end
end
