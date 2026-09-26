defmodule Edenflowers.Courses.RegistrationTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Courses

  defp register(course) do
    Courses.register_for_course(
      %{name: "Ada Lovelace", email: "ada@example.com", course_id: course.id, locale: "sv-FI"},
      actor: nil
    )
  end

  defp places_left(course) do
    Courses.get_course_by_id!(course.id, load: [:seats_left]).seats_left
  end

  test "snapshots the price and tax rate" do
    course = generate(course(price: "85.00", tax_rate_id: generate(tax_rate(percentage: "0.255")).id))

    assert {:ok, registration} = register(course)

    assert registration.status == :pending
    assert Decimal.equal?(registration.tax_rate, "0.255")
    assert Decimal.equal?(registration.amount, "85.00")
    assert registration.reference =~ ~r/^[0-9A-Z]{6}$/
  end

  test "a guest booking is linked to the user with its email" do
    course = generate(course())
    {:ok, user} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada", actor: Edenflowers.Actors.system_actor())

    assert {:ok, registration} = register(course)

    assert registration.user_id == user.id
  end

  test "a pending booking holds its place" do
    course = generate(course(total_places: 8))

    {:ok, _} = register(course)

    assert places_left(course) == 7
  end

  test "refuses a booking when the course is full" do
    course = generate(course(total_places: 1))
    generate(course_registration(course_id: course.id, status: :confirmed))

    assert {:error, error} = register(course)
    assert Exception.message(error) =~ "course is fully booked"
  end

  test "a pending booking older than the hold frees its place" do
    course = generate(course(total_places: 1))
    stale = DateTime.add(DateTime.utc_now(), -31, :minute)
    generate(course_registration(course_id: course.id, status: :pending, inserted_at: stale))

    assert places_left(course) == 1
    assert {:ok, _} = register(course)
  end

  test "cancelled bookings free their place" do
    course = generate(course(total_places: 1))
    generate(course_registration(course_id: course.id, status: :cancelled))

    assert places_left(course) == 1
  end

  test "refuses a booking after register_before" do
    course = generate(course(register_before: Date.add(Date.utc_today(), -2)))

    assert {:error, error} = register(course)
    assert Exception.message(error) =~ "booking has closed"
  end

  test "a guest cannot confirm their own booking" do
    course = generate(course())
    {:ok, registration} = register(course)

    assert {:error, %Ash.Error.Forbidden{}} = Courses.confirm_registration_payment(registration, actor: nil)
  end

  describe "adding a booking manually" do
    defp add_manually(course, actor) do
      Courses.add_registration_manually(
        %{name: "Ada Lovelace", email: "ada@example.com", course_id: course.id, locale: "sv-FI"},
        actor: actor
      )
    end

    test "confirms the booking without a payment" do
      course = generate(course())

      assert {:ok, registration} = add_manually(course, generate(admin_user()))
      assert registration.status == :confirmed
      assert registration.confirmed_at
      assert is_nil(registration.payment_intent_id)
    end

    test "is allowed after register_before but not beyond the course's places" do
      course = generate(course(register_before: Date.add(Date.utc_today(), -2), total_places: 1))
      admin = generate(admin_user())

      assert {:ok, _} = add_manually(course, admin)
      assert {:error, error} = add_manually(course, admin)
      assert Exception.message(error) =~ "course is fully booked"
    end

    test "is refused for customers" do
      assert {:error, %Ash.Error.Forbidden{}} = add_manually(generate(course()), nil)
    end
  end
end
