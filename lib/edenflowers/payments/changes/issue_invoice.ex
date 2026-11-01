defmodule Edenflowers.Payments.Changes.IssueInvoice do
  @moduledoc """
  Fills in a new invoice from its purchase: the frozen buyer details, today's
  date, and the defaults Jennie didn't override (amount, due date, language).

  The number is taken inside the insert's transaction, under a lock every
  invoice takes, as the last number + 1. A Postgres sequence would leave a
  gap whenever an insert rolled back; this way a failed insert frees its
  number for the next one, so the series stays gapless.
  """
  use Ash.Resource.Change

  import Ecto.Query, only: [from: 2]

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.ReferenceNumber
  alias Edenflowers.Repo
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

  # ponytail: one lock for every invoice; fine for one shop's handful a month.
  defp number(changeset) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('invoice_number'))")

    number =
      case Repo.one(from(i in "invoices", select: max(i.number))) do
        nil -> Invoice.first_number()
        last -> last + 1
      end

    changeset
    |> Ash.Changeset.force_change_attribute(:number, number)
    |> Ash.Changeset.force_change_attribute(:reference_number, ReferenceNumber.from_invoice_number(number))
  end
end
