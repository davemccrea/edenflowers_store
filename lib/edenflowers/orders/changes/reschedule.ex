defmodule Edenflowers.Orders.Changes.Reschedule do
  @moduledoc """
  Moves a subscription's next date when its interval or delivery day changes.

  A new interval counts from the latest delivery, not from the next one: going
  from every four weeks to every week brings the next delivery forward, rather
  than waiting out the four weeks first. The latest delivery is read from the
  orders, since "next date minus the interval" only holds while the next date
  is on the schedule.

  A new delivery day moves that date to the nearest one on the chosen weekday,
  up to three days either way. Either way, a date that lands inside the charge
  window moves on along the new schedule.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.Weekday
  alias Edenflowers.Orders.Changes.StepToScheduledDate
  alias Edenflowers.Orders.Subscription

  @impl true
  def change(changeset, _opts, context) do
    if Ash.Changeset.changing_attribute?(changeset, :interval_weeks) or new_day(changeset) do
      Ash.Changeset.before_action(changeset, &reschedule(&1, context))
    else
      changeset
    end
  end

  defp reschedule(changeset, context) do
    case Ash.load(changeset.data, :last_delivery_date, Ash.Context.to_opts(context, authorize?: false)) do
      {:ok, %{last_delivery_date: last, next_fulfillment_date: next, interval_weeks: old_weeks}} ->
        weeks = Ash.Changeset.get_attribute(changeset, :interval_weeks)

        base =
          if Ash.Changeset.changing_attribute?(changeset, :interval_weeks),
            do: Date.add(last || Date.add(next, -old_weeks * 7), weeks * 7),
            else: next

        next_date =
          base
          |> on_weekday(new_day(changeset))
          |> StepToScheduledDate.scheduled_date(weeks, Subscription.cutoff_days())

        Ash.Changeset.force_change_attribute(changeset, :next_fulfillment_date, next_date)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  # The chosen weekday when it differs from the one deliveries are on now.
  defp new_day(changeset) do
    case Ash.Changeset.get_argument(changeset, :delivery_day) do
      nil -> nil
      day -> if day != Weekday.from_date(changeset.data.next_fulfillment_date), do: day
    end
  end

  defp on_weekday(date, nil), do: date

  defp on_weekday(date, day) do
    shift = Weekday.to_integer(day) - Date.day_of_week(date)
    shift = if shift > 3, do: shift - 7, else: if(shift < -3, do: shift + 7, else: shift)
    Date.add(date, shift)
  end
end
