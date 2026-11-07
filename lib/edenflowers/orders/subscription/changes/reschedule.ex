defmodule Edenflowers.Orders.Subscription.Changes.Reschedule do
  @moduledoc """
  Moves a subscription's next date when its interval or delivery day changes,
  always onto its delivery day.

  A new interval counts from the latest delivery, not from the next one: going
  from every four weeks to every week brings the next delivery forward, rather
  than waiting out the four weeks first. The latest delivery is read from the
  orders, since "next date minus the interval" only holds while the next date
  is on the schedule. It may be on another weekday, an older delivery day or
  one Jennie agreed with the customer, so the date then moves onto the
  delivery day.

  A new delivery day moves that date forward to the first date on it, never
  back: an earlier one could leave a few days between two deliveries, and two
  charges close together, where a later one only makes one wait a little
  longer. Either way, a date that lands inside the charge window moves on
  along the new schedule.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.Weekday
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Orders.Subscription.Changes.StepToScheduledDate

  @impl true
  def change(changeset, _opts, context) do
    if Ash.Changeset.changing_attribute?(changeset, :interval_weeks) or
         Ash.Changeset.changing_attribute?(changeset, :delivery_day) do
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
          |> on_weekday(Ash.Changeset.get_attribute(changeset, :delivery_day))
          |> StepToScheduledDate.scheduled_date(weeks, Subscription.change_deadline_days())

        Ash.Changeset.force_change_attribute(changeset, :next_fulfillment_date, next_date)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp on_weekday(date, day), do: Date.add(date, rem(Weekday.to_integer(day) - Date.day_of_week(date) + 7, 7))
end
