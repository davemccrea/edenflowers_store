defmodule Edenflowers.Courses.Changes.KeepLateCancellationFee do
  @moduledoc """
  Cancelling less than 7 days before the course keeps the course's
  late-cancellation fee from what was paid, so the balance left to refund is
  the rest. Never more than was paid: an unpaid booking owes no fee.
  """

  use Ash.Resource.Change

  @full_refund_days 7

  @impl true
  def change(changeset, _opts, _context) do
    registration = Ash.load!(changeset.data, [:amount_paid, :course], authorize?: false, reuse_values?: false)
    course = registration.course

    if Date.diff(course.date, Edenflowers.ShopTime.today()) < @full_refund_days do
      fee = Decimal.min(course.late_cancellation_fee, Decimal.max(registration.amount_paid, 0))
      Ash.Changeset.force_change_attribute(changeset, :kept_amount, fee)
    else
      changeset
    end
  end
end
