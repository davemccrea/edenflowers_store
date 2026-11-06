defmodule EdenflowersWeb.Admin.DrawersTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias EdenflowersWeb.Admin.Drawers

  test "a button's failure flash gives the action's own reason, or stands alone without one" do
    registration = generate(course_registration(status: :confirmed, seats: 1))
    {:error, error} = Edenflowers.Courses.remove_registration_seat(registration, authorize?: false)

    assert Drawers.refusal_text(error, "Could not remove the seat.") ==
             "Could not remove the seat: cancel the booking to remove its last seat."

    assert Drawers.refusal_text(%RuntimeError{}, "Could not remove the seat.") == "Could not remove the seat."
  end
end
