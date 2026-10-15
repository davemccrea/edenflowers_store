defmodule Edenflowers.Orders.Changes.PrefillFromLastOrder do
  @moduledoc """
  Fills the delivery step from the signed-in customer's last order for
  themselves, so a returning customer doesn't retype their phone number and
  address. The fields stay editable in the form, and only empty ones are filled.

  Runs on entering the delivery step as well as on choosing an option: the
  option survives going back a step, so a returning order may never choose one.

  A gift delivery's address, instructions and phone are the recipient's, so
  they are never read from or written to one.

  Keyed on the actor, not the order's `user_id`: submitting contact details
  assigns even a guest to whichever account owns the typed email, and a guest
  must not see that account's address.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Orders.Order

  @impl true
  def change(changeset, _opts, %{actor: %{id: actor_id}}) do
    if changeset.data.user_id == actor_id and not gift_delivery?(changeset) do
      Ash.Changeset.before_action(changeset, &prefill(&1, actor_id))
    else
      changeset
    end
  end

  def change(changeset, _opts, _context), do: changeset

  defp prefill(changeset, actor_id) do
    case last_own_order(actor_id) do
      nil ->
        changeset

      last ->
        changeset
        |> prefill_phone(last)
        |> prefill_address(last)
    end
  end

  defp prefill_phone(changeset, last) do
    if is_nil(Ash.Changeset.get_attribute(changeset, :recipient_phone_number)) do
      Ash.Changeset.force_change_attribute(changeset, :recipient_phone_number, last.recipient_phone_number)
    else
      changeset
    end
  end

  # The geocode comes along so the summary can price the address straight
  # away. `submit_delivery` re-derives it server-side regardless.
  defp prefill_address(changeset, %{fulfillment_method: :delivery} = last) do
    if Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery and
         is_nil(Ash.Changeset.get_attribute(changeset, :delivery_address)) do
      Ash.Changeset.force_change_attributes(
        changeset,
        Map.take(last, [:delivery_address, :delivery_instructions, :geocoded_address, :distance])
      )
    else
      changeset
    end
  end

  defp prefill_address(changeset, _last), do: changeset

  defp last_own_order(actor_id) do
    Order
    |> Ash.Query.filter(
      state == :placed and user_id == ^actor_id and not (gift == true and fulfillment_method == :delivery)
    )
    |> Ash.Query.sort(ordered_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp gift_delivery?(changeset) do
    Ash.Changeset.get_attribute(changeset, :gift) == true and
      Ash.Changeset.get_attribute(changeset, :fulfillment_method) == :delivery
  end
end
