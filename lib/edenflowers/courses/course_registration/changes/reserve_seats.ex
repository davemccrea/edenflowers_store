defmodule Edenflowers.Courses.CourseRegistration.Changes.ReserveSeats do
  @moduledoc """
  Checks the course still takes bookings and has a place left, then snapshots
  what the booking costs.

  The course row is locked for the rest of the transaction, so two people
  booking the last place at once are counted one after the other.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Edenflowers.Courses.Course
  alias Edenflowers.Orders.Order.Changes.GenerateOrderReference

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      course_id = Ash.Changeset.get_attribute(changeset, :course_id)

      case lock_course(course_id) do
        nil -> Ash.Changeset.add_error(changeset, field: :course_id, message: "course not found")
        course -> reserve(changeset, course, opts[:allow_after_cutoff?] || false)
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

  defp reserve(changeset, course, allow_after_cutoff?) do
    cond do
      not allow_after_cutoff? and Date.before?(course.register_before, helsinki_today()) ->
        Ash.Changeset.add_error(changeset, field: :course_id, message: "booking has closed")

      course.seats_left < 1 ->
        Ash.Changeset.add_error(changeset, field: :course_id, message: "course is fully booked")

      true ->
        Ash.Changeset.force_change_attributes(changeset,
          reference: GenerateOrderReference.generate(),
          tax_rate: course.tax_rate.percentage,
          amount: course.price
        )
    end
  end

  defp helsinki_today, do: "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date()
end
