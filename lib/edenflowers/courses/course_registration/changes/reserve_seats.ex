defmodule Edenflowers.Courses.CourseRegistration.Changes.ReserveSeats do
  @moduledoc """
  Checks the course still takes bookings and has room for the requested seats,
  then snapshots what the booking costs.

  The course row is locked for the rest of the transaction, so two people
  booking the last seats at once are counted one after the other.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Ash.Error.Changes.InvalidAttribute
  alias Edenflowers.Courses.Course
  alias Edenflowers.Orders.Order.Changes.GenerateOrderReference

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      course_id = Ash.Changeset.get_attribute(changeset, :course_id)
      seats = Ash.Changeset.get_attribute(changeset, :seats)

      case lock_course(course_id) do
        nil -> Ash.Changeset.add_error(changeset, field: :course_id, message: "course not found")
        course -> reserve(changeset, course, seats, opts[:allow_after_cutoff?] || false)
      end
    end)
  end

  # Locked without loads: Postgres refuses FOR UPDATE on a query whose
  # aggregates arrive through outer joins, so seats are counted separately.
  defp lock_course(course_id) do
    Course
    |> Ash.Query.filter(id == ^course_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> nil
      course -> Ash.load!(course, [:seats_left, :tax_rate], authorize?: false)
    end
  end

  defp reserve(changeset, course, seats, allow_after_cutoff?) do
    cond do
      not allow_after_cutoff? and Date.before?(course.register_before, helsinki_today()) ->
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
          reference: GenerateOrderReference.generate(),
          tax_rate: course.tax_rate.percentage,
          amount: Decimal.mult(course.price, seats)
        )
    end
  end

  defp helsinki_today, do: "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()
end
