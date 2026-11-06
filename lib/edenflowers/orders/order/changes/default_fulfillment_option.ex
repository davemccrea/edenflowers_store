defmodule Edenflowers.Orders.Order.Changes.DefaultFulfillmentOption do
  @moduledoc """
  Chooses checkout's first fulfillment option for a cart entering the delivery
  step without one, so the step opens with an option and its fields showing.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment

  @impl true
  def change(changeset, _opts, _context) do
    with nil <- Ash.Changeset.get_attribute(changeset, :fulfillment_option_id),
         {:ok, [%{id: id} | _]} <- Fulfillment.list_options_for_checkout(authorize?: false) do
      Ash.Changeset.force_change_attribute(changeset, :fulfillment_option_id, id)
    else
      _chosen_or_no_options -> changeset
    end
  end
end
