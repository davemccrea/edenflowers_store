defmodule Edenflowers.Courses.CourseRegistration.Changes.PriceBooking do
  @moduledoc """
  Snapshots the booking amount and VAT rate. Online bookings must meet the
  deadline and seat limit; `manual?: true` skips those checks.

  Pending bookings do not reserve seats. Concurrent payments for the last
  place can both confirm, leaving Jennie to accommodate the extra booking.
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
        {:ok, course} -> price(changeset, course, seats, opts[:manual?] || false)
        {:error, _not_found} -> Ash.Changeset.add_error(changeset, field: :course_id, message: "course not found")
      end
    end)
  end

  defp price(changeset, course, seats, manual?) do
    cond do
      not manual? and Date.before?(course.register_before, Edenflowers.ShopTime.today()) ->
        Ash.Changeset.add_error(changeset, field: :course_id, message: "booking has closed")

      not manual? and seats > course.seats_left ->
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
