defmodule Edenflowers.Courses.CourseRegistrationTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Courses
  alias Edenflowers.Expressions.HelsinkiToday

  defp register(course, seats) do
    Courses.register_for_course(
      %{name: "Ada Lovelace", email: "ada@example.com", seats: seats, course_id: course.id, locale: "sv-FI"},
      actor: nil
    )
  end

  defp seats_left(course) do
    Courses.get_course_by_id!(course.id, load: [:seats_left]).seats_left
  end

  test "snapshots the price, tax rate and total for the seats booked" do
    course = generate(course(price: "85.00", tax_rate_id: generate(tax_rate(percentage: "0.255")).id))

    assert {:ok, registration} = register(course, 3)

    assert registration.status == :pending
    assert Decimal.equal?(registration.tax_rate, "0.255")
    assert Decimal.equal?(registration.amount, "255.00")
    assert registration.reference =~ ~r/^\d+$/
  end

  test "rejects an email address without a domain" do
    assert {:error, error} =
             Courses.register_for_course(
               %{name: "Ada Lovelace", email: "ada@", seats: 1, course_id: generate(course()).id, locale: "sv-FI"},
               actor: nil
             )

    assert Exception.message(error) =~ "Must be a valid email address"
  end

  test "course prices are expressed in whole cents" do
    course = generate(course())

    assert {:error, error} =
             course
             |> Ash.Changeset.for_update(:update, %{price: "85.555"})
             |> Ash.update(authorize?: false)

    assert Exception.message(error) =~ "no more than 2 decimal places"
  end

  test "a guest booking is linked to the user with its email" do
    course = generate(course())
    {:ok, user} = Edenflowers.Accounts.upsert_user("ada@example.com", "Ada", actor: Edenflowers.Actors.system_actor())

    assert {:ok, registration} = register(course, 1)

    assert registration.user_id == user.id
  end

  test "a pending booking holds its seats" do
    course = generate(course(total_places: 8))

    {:ok, _} = register(course, 3)

    assert seats_left(course) == 5
  end

  test "refuses more seats than are left" do
    course = generate(course(total_places: 4))
    generate(course_registration(course_id: course.id, seats: 3, status: :confirmed))

    assert {:error, error} = register(course, 2)
    assert Exception.message(error) =~ "only 1 places left"
  end

  test "a pending booking older than the hold frees its seats" do
    course = generate(course(total_places: 4))
    stale = DateTime.add(DateTime.utc_now(), -31, :minute)
    generate(course_registration(course_id: course.id, seats: 4, status: :pending, inserted_at: stale))

    assert seats_left(course) == 4
    assert {:ok, _} = register(course, 4)
  end

  test "cancelled bookings free their seats" do
    course = generate(course(total_places: 4))
    generate(course_registration(course_id: course.id, seats: 4, status: :cancelled))

    assert seats_left(course) == 4
  end

  test "booking is open on register_before itself and closed the day after" do
    today = HelsinkiToday.today()

    assert {:ok, _} = register(generate(course(register_before: today)), 1)

    assert {:error, error} = register(generate(course(register_before: Date.add(today, -1))), 1)
    assert Exception.message(error) =~ "booking has closed"
  end

  test "a guest cannot confirm their own booking" do
    course = generate(course())
    {:ok, registration} = register(course, 1)

    {:ok, registration} =
      Courses.add_registration_payment_intent_id(registration, "pi_guest", actor: Edenflowers.Actors.system_actor())

    assert {:error, %Ash.Error.Forbidden{}} =
             Courses.confirm_registration_payment(registration, "pi_guest", %{amount_paid: registration.amount},
               actor: nil
             )
  end

  describe "adding a booking manually" do
    defp add_manually(course, seats, actor) do
      Courses.add_registration_manually(
        %{name: "Ada Lovelace", email: "ada@example.com", seats: seats, course_id: course.id, locale: "sv-FI"},
        actor: actor
      )
    end

    test "confirms the booking without a payment" do
      course = generate(course())

      assert {:ok, registration} = add_manually(course, 2, generate(admin_user()))
      assert registration.status == :confirmed
      assert registration.confirmed_at
      assert is_nil(registration.payment_intent_id)
    end

    test "is allowed after register_before but not beyond the course's places" do
      course = generate(course(register_before: Date.add(Date.utc_today(), -2), total_places: 3))
      admin = generate(admin_user())

      assert {:ok, _} = add_manually(course, 2, admin)
      assert {:error, error} = add_manually(course, 2, admin)
      assert Exception.message(error) =~ "only 1 places left"
    end

    test "is refused for customers" do
      assert {:error, %Ash.Error.Forbidden{}} = add_manually(generate(course()), 1, nil)
    end
  end

  describe "paying at the course" do
    setup do
      admin = generate(admin_user())
      {:ok, registration} = add_manually(generate(course(price: "85.00")), 2, admin)
      %{admin: admin, registration: registration}
    end

    test "a manual booking owes its price until it is marked paid", %{admin: admin, registration: registration} do
      assert Decimal.equal?(balance(registration), "170.00")

      assert {:ok, _paid} = Courses.mark_registration_paid(registration, :mobilepay, actor: admin)

      assert [%{method: :mobilepay, amount: amount}] = Ash.load!(registration, :payments, authorize?: false).payments
      assert Decimal.equal?(amount, "170.00")
      assert Decimal.equal?(balance(registration), 0)
    end

    test "is marked paid only while something is owed", %{admin: admin, registration: registration} do
      assert {:ok, _paid} = Courses.mark_registration_paid(registration, :cash, actor: admin)

      assert {:error, error} = Courses.mark_registration_paid(registration, :cash, actor: admin)
      assert Exception.message(error) =~ "nothing is owed"
    end

    test "is paid in person, not through Stripe", %{admin: admin, registration: registration} do
      assert {:error, _error} = Courses.mark_registration_paid(registration, :stripe, actor: admin)
    end

    test "a paid booking owes a refund after a seat is removed or it is cancelled", %{
      admin: admin,
      registration: registration
    } do
      {:ok, registration} = Courses.mark_registration_paid(registration, :cash, actor: admin)

      {:ok, registration} = Courses.remove_registration_seat(registration, actor: admin)
      assert Decimal.equal?(balance(registration), "-85.00")

      {:ok, registration} = Courses.cancel_registration(registration, actor: admin)
      assert Decimal.equal?(balance(registration), "-170.00")
    end

    test "money taken in person is refunded in person, even on a cancelled booking", %{
      admin: admin,
      registration: registration
    } do
      {:ok, registration} = Courses.mark_registration_paid(registration, :cash, actor: admin)
      {:ok, registration} = Courses.cancel_registration(registration, actor: admin)

      assert {:error, error} =
               Courses.record_registration_in_person_refund(registration, "-170.01", :cash, actor: admin)

      assert Exception.message(error) =~ "is more than was paid in person"

      assert {:ok, registration} =
               Courses.record_registration_in_person_refund(registration, "-170.00", :mobilepay, actor: admin)

      assert Decimal.equal?(balance(registration), 0)
    end

    test "an in-person refund can't hand back money paid through Stripe", %{admin: admin} do
      registration = generate(course_registration(status: :confirmed, payment_intent_id: "pi_paid"))

      generate(
        payment(course_registration_id: registration.id, amount: registration.amount, payment_intent_id: "pi_paid")
      )

      Mox.stub(Edenflowers.External.StripeAPI.Mock, :cancel_payment_intent, fn intent -> {:ok, intent} end)
      {:ok, registration} = Courses.cancel_registration(registration, actor: admin)

      assert {:error, _error} =
               Courses.record_registration_in_person_refund(registration, "-1.00", :cash, actor: admin)
    end

    test "an in-person refund must be negative", %{admin: admin, registration: registration} do
      {:ok, registration} = Courses.mark_registration_paid(registration, :cash, actor: admin)

      assert {:error, error} = Courses.record_registration_in_person_refund(registration, "10.00", :cash, actor: admin)
      assert Exception.message(error) =~ "must be a refund"
    end
  end

  defp balance(registration) do
    Ash.load!(registration, :balance, authorize?: false, reuse_values?: false).balance
  end

  test "removing seats stops at the last one, which needs a cancel" do
    admin = generate(admin_user())
    {:ok, registration} = add_manually(generate(course()), 2, admin)

    assert {:ok, registration} = Courses.remove_registration_seat(registration, actor: admin)
    assert registration.removed_seats == 1

    assert {:error, error} = Courses.remove_registration_seat(registration, actor: admin)
    assert Exception.message(error) =~ "cancel the booking to remove its last seat"
  end
end
