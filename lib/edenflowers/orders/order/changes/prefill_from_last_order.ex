defmodule Edenflowers.Orders.Order.Changes.PrefillFromLastOrder do
  @moduledoc """
  Fills the delivery step from the signed-in customer's last orders, so a
  returning customer doesn't retype their phone number and address. The
  fields stay editable in the form, and only empty ones are filled.

  Runs on entering the delivery step as well as on choosing an option: the
  option survives going back a step, so a returning order may never choose one.

  The phone is the Customer's own `customer_phone_number`, taken from the last
  order that has one. A Recipient's number is never filled. The address comes
  from the last order the Customer didn't send as a gift, and only goes on an
  order that isn't one either.

  Keyed on the actor, not the order's `user_id`: submitting contact details
  assigns even a guest to whichever account owns the typed email, and a guest
  must not see that account's address.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, _opts, %{actor: %{id: actor_id}}) do
    if changeset.data.user_id == actor_id do
      Ash.Changeset.before_action(changeset, &prefill(&1, actor_id))
    else
      changeset
    end
  end

  def change(changeset, _opts, _context), do: changeset

  defp prefill(changeset, actor_id) do
    changeset
    |> prefill_phone(actor_id)
    |> prefill_address(actor_id)
  end

  defp prefill_phone(changeset, actor_id) do
    if is_nil(Ash.Changeset.get_attribute(changeset, :customer_phone_number)) do
      case Orders.get_last_order_with_customer_phone!(actor_id, authorize?: false, not_found_error?: false) do
        nil -> changeset
        last -> Ash.Changeset.force_change_attribute(changeset, :customer_phone_number, last.customer_phone_number)
      end
    else
      changeset
    end
  end

  # The geocode comes along so the summary can price the address straight
  # away. `submit_delivery` re-derives it server-side regardless.
  defp prefill_address(changeset, actor_id) do
    if own_delivery?(changeset) and is_nil(Ash.Changeset.get_attribute(changeset, :delivery_address)) do
      case last_own_delivery(actor_id) do
        nil ->
          changeset

        last ->
          Ash.Changeset.force_change_attributes(
            changeset,
            Map.take(last, [:delivery_address, :delivery_instructions, :geocoded_address, :distance])
          )
      end
    else
      changeset
    end
  end

  defp last_own_delivery(actor_id) do
    Order
    |> Ash.Query.filter(state == :placed and user_id == ^actor_id and fulfillment_method == :delivery and not gift)
    |> Ash.Query.sort(ordered_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp own_delivery?(changeset) do
    Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery and
      not Ash.Changeset.get_attribute(changeset, :gift)
  end
end
