defmodule Edenflowers.Orders.Changes.StepToScheduledDate do
  @moduledoc """
  Moves a Subscription's next date on by whole intervals to the first date on
  its schedule at least `days_from_today` days after today in Helsinki. A date
  already that far away is kept.
  """
  use Ash.Resource.Change

  alias Edenflowers.Expressions.HelsinkiToday

  @impl true
  def change(changeset, opts, _context) do
    %{next_fulfillment_date: date, interval_weeks: weeks} = changeset.data
    earliest = Date.add(HelsinkiToday.today(), Keyword.fetch!(opts, :days_from_today))

    next_date =
      date
      |> Stream.iterate(&Date.add(&1, weeks * 7))
      |> Enum.find(&(not Date.before?(&1, earliest)))

    Ash.Changeset.force_change_attribute(changeset, :next_fulfillment_date, next_date)
  end
end
