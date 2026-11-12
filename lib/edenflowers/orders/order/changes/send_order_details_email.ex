defmodule Edenflowers.Orders.Order.Changes.SendOrderDetailsEmail do
  @moduledoc """
  Emails the order as it stands, with its payment link when one is open: as
  Order details when Jennie places a custom order (`email: :order_details`),
  Order updated after she edits one (`:order_updated`), Subscription
  payment failed for an Occurrence whose card was refused
  (`:subscription_payment_failed`), or the Payment reminder she sends by
  hand (`:payment_reminder`).
  """

  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Email
  alias Edenflowers.Email.Edits
  alias Edenflowers.Mailer

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      # Read fresh: the admin page's copy can predate a payment, and the
      # email says what's owed.
      order = Ash.get!(Edenflowers.Orders.Order, changeset.data.id, load: load(), authorize?: false)

      case Keyword.fetch!(opts, :email) do
        :payment_reminder when not order.payable? -> Ash.Changeset.add_error(changeset, "has nothing to pay")
        :subscription_payment_failed when order.state != :placed or order.cancelled? or not order.payable? -> changeset
        kind -> deliver(changeset, order, kind)
      end
    end)
  end

  defp deliver(changeset, order, kind) do
    edits = Edits.from_changeset(changeset)
    url = payment_link_url(order, kind, Ash.Changeset.get_attribute(changeset, :payment_link_token))

    case order |> email(kind, url) |> Edits.apply_to(edits, url) |> Mailer.deliver() do
      {:ok, _result} ->
        Logger.info("Sent #{kind} email for order #{order.id}")

        changeset
        |> stamp(kind)
        |> Ash.Changeset.set_context(%{paper_trail_metadata: Edits.for_log(edits)})
        |> clear_failure()

      {:error, error} ->
        Ash.Changeset.add_error(changeset, "Failed to send #{kind} email: #{inspect(error)}")
    end
  end

  @doc "What the order is loaded with to build its email."
  def load do
    [
      :customer_first_name,
      :grand_total,
      :amount_paid,
      :balance,
      :payment_link_open?,
      :payable?,
      :cancelled?,
      line_items: [:subtotal]
    ]
  end

  @doc "The `kind` email for an order loaded with `load/0`, giving the payment link at `url` if there is one."
  def email(order, :order_details, url), do: Email.order_details(order, url)
  def email(order, :order_updated, url), do: Email.order_updated(order, url)
  def email(order, :subscription_payment_failed, url), do: Email.subscription_payment_failed(order, url)
  def email(order, :payment_reminder, url), do: Email.payment_reminder(order, url)

  @doc """
  The payment link the `kind` email gives. A reminder gives the link sending
  it opens, whose `token` isn't in the order read before yet; any other
  email gives a link only while one is open.
  """
  def payment_link_url(order, :payment_reminder, token),
    do: EdenflowersWeb.PaymentLink.url_for(%{order | payment_link_token: token})

  def payment_link_url(order, _kind, _token), do: EdenflowersWeb.PaymentLink.url_if_open(order)

  # A reminder isn't the order's details, so the menu still offers to send them.
  defp stamp(changeset, :payment_reminder), do: changeset

  defp stamp(changeset, _kind),
    do: Ash.Changeset.force_change_attribute(changeset, :order_details_emailed_at, DateTime.utc_now())

  # Clear the failure in the database even if the caller's stale record already has a nil timestamp.
  defp clear_failure(changeset), do: Ash.Changeset.atomic_update(changeset, :order_details_email_failed_at, nil)
end
