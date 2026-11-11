defmodule Edenflowers.Orders.Subscription.Changes.Reschedule do
  @moduledoc """
  Moves a subscription's next date when its interval or delivery day changes:
  to the first date on the delivery day at least one interval after the
  latest delivery.

  Counting from the latest delivery, not the next date, means going from
  every four weeks to every week brings the next delivery forward rather than
  waiting out the four weeks, and changing the day back and forth always
  lands on the same dates instead of drifting further out. The latest
  delivery is read from the orders, since "next date minus the interval" only
  holds while the next date is on the schedule.

  After adding the new interval to the latest delivery, move forward to the
  chosen weekday, never backward to an earlier weekday. Moving backward could
  put two deliveries and their charges too close together. If the resulting
  date is already past the change cutoff, advance by whole intervals on the
  new schedule until changes are still allowed.
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
    case next_fulfillment_date(changeset, Ash.Context.to_opts(context, authorize?: false)) do
      {:ok, next_date} ->
        Ash.Changeset.force_change_attribute(changeset, :next_fulfillment_date, next_date)

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  @doc false
  def next_fulfillment_date(changeset, opts) do
    if Ash.Changeset.changing_attribute?(changeset, :interval_weeks) or
         Ash.Changeset.changing_attribute?(changeset, :delivery_day) do
      rescheduled_date(changeset, opts)
    else
      {:ok, changeset.data.next_fulfillment_date}
    end
  end

  defp rescheduled_date(changeset, opts) do
    case Ash.load(changeset.data, :last_delivery_date, opts) do
      {:ok, %{last_delivery_date: last, next_fulfillment_date: next, interval_weeks: old_weeks}} ->
        weeks = Ash.Changeset.get_attribute(changeset, :interval_weeks)

        next_date =
          (last || Date.add(next, -old_weeks * 7))
          |> Date.add(weeks * 7)
          |> on_weekday(Ash.Changeset.get_attribute(changeset, :delivery_day))
          |> StepToScheduledDate.scheduled_date(weeks, Subscription.change_deadline_days())

        {:ok, next_date}

      {:error, error} ->
        {:error, error}
    end
  end

  defp on_weekday(date, day), do: Date.add(date, rem(Weekday.to_integer(day) - Date.day_of_week(date) + 7, 7))
end
