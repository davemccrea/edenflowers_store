defmodule Edenflowers.Courses.Changes.PriceBooking do
  @moduledoc """
  Refuses a course that has closed or hasn't room for the requested seats,
  then snapshots what the booking costs.

  Nothing is held: places are counted from paid bookings, so two people
  paying for the last place at once are both booked and Jennie makes room.
  """

  use Ash.Resource.Change

  alias Ash.Error.Changes.InvalidAttribute
  alias Edenflowers.Courses.Course

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      course_id = Ash.Changeset.get_attribute(changeset, :course_id)
      seats = Ash.Changeset.get_attribute(changeset, :seats)

      case Ash.get(Course, course_id, load: [:seats_left, :tax_rate], authorize?: false) do
        {:ok, course} -> price(changeset, course, seats, opts[:allow_after_cutoff?] || false)
        {:error, _not_found} -> Ash.Changeset.add_error(changeset, field: :course_id, message: "course not found")
      end
    end)
  end

  defp price(changeset, course, seats, allow_after_cutoff?) do
    cond do
      not allow_after_cutoff? and Date.before?(course.register_before, Edenflowers.ShopTime.today()) ->
        Ash.Changeset.add_error(changeset, field: :course_id, message: "booking has closed")

      seats > course.seats_left ->
        Ash.Changeset.add_error(
          changeset,
          InvalidAttribute.exception(
            field: :seats,
            message: "only %{count} places left",
            vars: [count: course.seats_left]
          )
        )

      true ->
        Ash.Changeset.force_change_attributes(changeset,
          tax_rate: course.tax_rate.percentage,
          amount: Decimal.mult(course.price, seats)
        )
    end
  end
end
