defmodule Edenflowers.Courses.CourseRegistrationTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Courses
  alias Edenflowers.ShopTime

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
    today = ShopTime.today()

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
      course = generate(course(register_before: Date.add(ShopTime.today(), -2), total_places: 3))
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

    test "a manual booking owes its price until it is paid at the course", %{admin: admin, registration: registration} do
      assert Decimal.equal?(balance(registration), "170.00")

      assert {:ok, _paid} = Courses.record_registration_payment(registration, "170.00", :mobilepay, actor: admin)

      assert [%{method: :mobilepay, amount: amount}] = Ash.load!(registration, :payments, authorize?: false).payments
      assert Decimal.equal?(amount, "170.00")
      assert Decimal.equal?(balance(registration), 0)
    end

    test "a paid booking owes a refund after a seat is removed or it is cancelled", %{
      admin: admin,
      registration: registration
    } do
      {:ok, registration} = Courses.record_registration_payment(registration, "170.00", :cash, actor: admin)

      {:ok, registration} = Courses.remove_registration_seat(registration, actor: admin)
      assert Decimal.equal?(balance(registration), "-85.00")

      {:ok, registration} = Courses.cancel_registration(registration, actor: admin)
      assert Decimal.equal?(balance(registration), "-170.00")

      assert {:ok, registration} =
               Ash.update(registration, %{amount: "170.00", payment_method: :cash}, action: :refund, actor: admin)

      assert Decimal.equal?(balance(registration), 0)
    end
  end

  describe "cancelling a paid booking" do
    setup do
      %{admin: generate(admin_user())}
    end

    defp paid_booking(days_before, admin) do
      today = ShopTime.today()
      course = generate(course(date: Date.add(today, days_before), register_before: today))

      {:ok, registration} = add_manually(course, 1, admin)
      {:ok, registration} = Courses.record_registration_payment(registration, "85.00", :cash, actor: admin)
      registration
    end

    test "leaves everything paid to refund, however close the course", %{admin: admin} do
      {:ok, registration} = Courses.cancel_registration(paid_booking(1, admin), actor: admin)
      assert Decimal.equal?(balance(registration), "-85.00")
    end

    test "emails the customer the reason, unless Jennie unticks it", %{admin: admin} do
      {:ok, registration} =
        Courses.cancel_registration(paid_booking(1, admin), %{cancellation_reason: "Jag är sjuk."}, actor: admin)

      assert registration.cancellation_emailed_to == "ada@example.com"
      [job] = all_enqueued(worker: Edenflowers.Courses.Workers.SendCancelledEmail)
      assert :ok = perform_job(Edenflowers.Courses.Workers.SendCancelledEmail, job.args)

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.text_body =~ "Jag är sjuk."
      end)

      {:ok, quiet} = Courses.cancel_registration(paid_booking(1, admin), %{email_customer?: false}, actor: admin)
      assert quiet.cancellation_emailed_to == nil
      assert [_only_the_first] = all_enqueued(worker: Edenflowers.Courses.Workers.SendCancelledEmail)
    end

    test "releasing a hold the customer never paid for emails nobody" do
      {:ok, hold} = register(generate(course()), 1)

      {:ok, _released} = Courses.cancel_registration(hold, actor: Edenflowers.Actors.system_actor())

      refute_enqueued(worker: Edenflowers.Courses.Workers.SendCancelledEmail)
    end

    test "Jennie keeps what she chooses, but not more than was paid", %{admin: admin} do
      {:ok, registration} = Courses.cancel_registration(paid_booking(1, admin), %{kept_amount: "35.00"}, actor: admin)
      assert Decimal.equal?(balance(registration), "-50.00")

      assert {:error, error} =
               Courses.cancel_registration(paid_booking(1, admin), %{kept_amount: "85.01"}, actor: admin)

      assert Exception.message(error) =~ "more than was paid"
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
