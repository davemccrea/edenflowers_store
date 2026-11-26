defmodule Edenflowers.Orders.Order.Changes.StartRepeat do
  @moduledoc "Starts the Repeating order this Custom Order is the first of, its next date `repeat_every_weeks` on."
  use Ash.Resource.Change

  alias Edenflowers.Orders.OrderRepeat

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      weeks = Ash.Changeset.get_argument(changeset, :repeat_every_weeks)
      first = Ash.Changeset.get_attribute(changeset, :fulfillment_date)

      repeat =
        OrderRepeat
        |> Ash.Changeset.for_create(:start, %{every_weeks: weeks, next_on: Date.add(first, weeks * 7)},
          authorize?: false
        )
        |> Ash.create!()

      Ash.Changeset.force_change_attribute(changeset, :order_repeat_id, repeat.id)
    end)
  end
end
