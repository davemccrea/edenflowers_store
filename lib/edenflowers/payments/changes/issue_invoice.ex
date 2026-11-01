defmodule Edenflowers.Payments.Changes.IssueInvoice do
  @moduledoc """
  Fills in a new invoice from its purchase: the frozen buyer details, today's
  date, and the defaults Jennie didn't override (amount, due date, language).

  The number is the next in the series it shares with Credit notes
  (`NumberSeries`), taken just before the insert.
  """
  use Ash.Resource.Change

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.NumberSeries
  alias Edenflowers.Payments.ReferenceNumber
  alias Edenflowers.ShopTime

  @impl true
  def change(changeset, _opts, _context) do
    case Invoice.purchase(changeset, [:uninvoiced_balance]) do
      nil ->
        changeset

      purchase ->
        today = ShopTime.today()

        changeset
        |> Ash.Changeset.force_change_attributes(buyer(purchase))
        |> Ash.Changeset.force_change_attribute(:invoice_date, today)
        |> Ash.Changeset.change_new_attribute(:due_date, Invoice.default_due_date())
        |> Ash.Changeset.change_new_attribute(:locale, purchase.locale)
        |> default_amount(purchase.uninvoiced_balance)
        |> Ash.Changeset.before_action(&number/1)
    end
  end

  @doc "The buyer details an invoice for `purchase` freezes, as Invoice attributes."
  def buyer(%Order{} = order) do
    own_delivery? = order.fulfillment_method == :delivery and not order.gift

    Map.merge(business(order), %{
      buyer_name: order.customer_name,
      buyer_email: order.customer_email,
      buyer_address: if(own_delivery?, do: order.delivery_address)
    })
  end

  def buyer(%CourseRegistration{} = registration) do
    Map.merge(business(registration), %{
      buyer_name: registration.name,
      buyer_email: registration.email,
      buyer_address: nil
    })
  end

  # Details left behind when Jennie unticked Business customer aren't the buyer's.
  defp business(%{business_customer: false}), do: %{business_customer: false}

  defp business(purchase) do
    Map.take(purchase, [:business_customer, :company_name, :business_id, :billing_address, :customer_reference])
  end

  defp default_amount(changeset, uninvoiced) do
    if Decimal.positive?(uninvoiced),
      do: Ash.Changeset.change_new_attribute(changeset, :amount, uninvoiced),
      else: changeset
  end

  defp number(changeset) do
    number = NumberSeries.take()

    changeset
    |> Ash.Changeset.force_change_attribute(:number, number)
    |> Ash.Changeset.force_change_attribute(:reference_number, ReferenceNumber.from_invoice_number(number))
  end
end
