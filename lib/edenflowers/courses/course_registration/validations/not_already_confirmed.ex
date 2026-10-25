defmodule Edenflowers.Courses.CourseRegistration.Validations.NotAlreadyConfirmed do
  @moduledoc "Fails with `AlreadyPaid` when the booking is already confirmed."
  use Ash.Resource.Validation

  alias Edenflowers.Payments.Errors.AlreadyPaid

  @impl true
  def atomic(_changeset, _opts, _context) do
    {:atomic, [:status], expr(status == :confirmed), expr(error(^AlreadyPaid, %{}))}
  end
end
