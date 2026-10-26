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

  test "only paid places count: a registration still at checkout holds none" do
    course = generate(course(total_places: 8))

    {:ok, _} = register(course, 3)
    generate(course_registration(course_id: course.id, seats: 2, status: :confirmed))

    assert seats_left(course) == 6
  end

  test "refuses more seats than are left" do
    course = generate(course(total_places: 4))
    generate(course_registration(course_id: course.id, seats: 3, status: :confirmed))

    assert {:error, error} = register(course, 2)
    assert Exception.message(error) =~ "only 1 places left"
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

    test "confirms places immediately without a payment, receipt or automatic link" do
      course = generate(course(total_places: 5))

      assert {:ok, registration} = add_manually(course, 2, generate(admin_user()))
      assert registration.status == :confirmed
      assert registration.confirmed_at
      refute registration.payment_link_token
      refute registration.receipt_emailed_at
      assert seats_left(course) == 3
      assert Ash.load!(registration, :payments, authorize?: false).payments == []

      assert_enqueued(
        worker: Edenflowers.Courses.Workers.SendConfirmationEmail,
        args: %{"primary_key" => %{"id" => registration.id}}
      )
    end

    test "is allowed after register_before and beyond the course's free places" do
      course = generate(course(register_before: Date.add(ShopTime.today(), -2), total_places: 3))
      generate(course_registration(course_id: course.id, seats: 2, status: :confirmed))
      admin = generate(admin_user())

      assert {:ok, _} = add_manually(course, 1, admin)
      assert {:ok, _} = add_manually(course, 2, admin)
      assert seats_left(course) == -2
    end

    test "is refused for customers" do
      assert {:error, %Ash.Error.Forbidden{}} = add_manually(generate(course()), 1, nil)
    end

    test "payment terms persist without treating a link or invoice as money received" do
      course = generate(course(total_places: 10))
      admin = generate(admin_user())

      for terms <- [:payment_link, :invoice, :on_fulfillment] do
        assert {:ok, booking} =
                 Courses.add_registration_manually(
                   %{
                     name: "Ada",
                     email: "ada@example.com",
                     course_id: course.id,
                     payment_terms: terms,
                     email_customer?: false
                   },
                   actor: admin
                 )

        booking = Ash.load!(booking, [:payments, :balance], authorize?: false)
        assert booking.status == :confirmed
        assert booking.payment_terms == terms
        assert is_binary(booking.payment_link_token) == (terms == :payment_link)
        assert booking.payments == []
        assert Decimal.equal?(booking.balance, "85.00")
        refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
      end

      assert seats_left(course) == 7
    end

    test "an initial received payment uses the ledger and records its real method" do
      course = generate(course())
      admin = generate(admin_user())

      assert {:ok, registration} =
               Courses.add_registration_manually(
                 %{
                   name: "Ada",
                   email: "ada@example.com",
                   seats: 2,
                   course_id: course.id,
                   amount: "100.00",
                   payment_method: :zettle,
                   email_customer?: false
                 },
                 actor: admin
               )

      registration = Ash.load!(registration, [:payments, :balance], authorize?: false)
      assert registration.status == :confirmed
      assert [%{method: :zettle, amount: amount}] = registration.payments
      assert Decimal.equal?(amount, "100.00")
      assert Decimal.equal?(registration.balance, "70.00")
      assert seats_left(course) == 6
      refute registration.payment_link_token
      refute_enqueued(worker: Edenflowers.Courses.Workers.SendConfirmationEmail)
    end

    test "an invalid initial payment rolls the entire booking back" do
      course = generate(course())
      admin = generate(admin_user())

      for payment <- [
            %{amount: "85.00"},
            %{payment_method: :cash},
            %{amount: "86.00", payment_method: :cash},
            %{amount: "85.00", payment_method: :stripe}
          ] do
        assert {:error, _error} =
                 Courses.add_registration_manually(
                   Map.merge(%{name: "Ada", email: "ada@example.com", seats: 1, course_id: course.id}, payment),
                   actor: admin
                 )
      end

      assert Ash.count!(Edenflowers.Courses.CourseRegistration, authorize?: false) == 0
      assert seats_left(course) == 8
    end

    test "cancelling a never-paid accepted booking frees its places without inventing a refund" do
      course = generate(course(cancellation_fee_percent: 100))
      admin = generate(admin_user())
      {:ok, registration} = add_manually(course, 2, admin)
      assert seats_left(course) == 6
      assert {:ok, cancelled} = Courses.cancel_registration(registration, %{email_customer?: false}, actor: admin)
      assert cancelled.status == :cancelled
      assert Decimal.equal?(balance(cancelled), 0)
      assert Ash.load!(cancelled, :payments, authorize?: false).payments == []
      assert seats_left(course) == 8
    end
  end

  # Paid in person, as bookings could be before courses were paid by link,
  # so handing money back needs no Stripe.
  defp pay(registration, amount) do
    generate(payment(course_registration_id: registration.id, method: :cash, amount: Decimal.new(amount)))
    Ash.Seed.update!(registration, %{status: :confirmed})
  end

  describe "paying" do
    setup do
      admin = generate(admin_user())
      {:ok, registration} = add_manually(generate(course(price: "85.00")), 2, admin)
      %{admin: admin, registration: registration}
    end

    test "a manual booking owes its price until it is paid", %{registration: registration} do
      assert Decimal.equal?(balance(registration), "170.00")
    end

    test "manual collection uses the shared ledger", %{admin: admin, registration: registration} do
      assert {:ok, paid} =
               Ash.update(registration, %{amount: "170.00", payment_method: :cash},
                 action: :record_payment,
                 actor: admin
               )

      assert Decimal.equal?(balance(paid), 0)
      assert [%{method: :cash}] = Ash.load!(paid, :payments, authorize?: false).payments
    end

    test "a paid booking owes a refund after a seat is removed or it is cancelled", %{
      admin: admin,
      registration: registration
    } do
      registration = pay(registration, "170.00")

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

    defp paid_booking(days_before, admin, fee_percent \\ 0) do
      today = ShopTime.today()

      course =
        generate(
          course(date: Date.add(today, days_before), register_before: today, cancellation_fee_percent: fee_percent)
        )

      {:ok, registration} = add_manually(course, 1, admin)
      pay(registration, "85.00")
    end

    test "leaves everything paid to refund, however close the course", %{admin: admin} do
      {:ok, registration} = Courses.cancel_registration(paid_booking(1, admin), actor: admin)
      assert Decimal.equal?(balance(registration), "-85.00")
    end

    test "keeps the course's fee once its cancellation deadline has passed", %{admin: admin} do
      {:ok, late} = Courses.cancel_registration(paid_booking(1, admin, 50), actor: admin)
      assert Decimal.equal?(late.kept_amount, "42.50")
      assert Decimal.equal?(balance(late), "-42.50")

      {:ok, early} = Courses.cancel_registration(paid_booking(7, admin, 50), actor: admin)
      assert Decimal.equal?(early.kept_amount, 0)
      assert Decimal.equal?(balance(early), "-85.00")
    end

    test "emails the customer the reason, unless Jennie unticks it", %{admin: admin} do
      {:ok, registration} =
        Courses.cancel_registration(paid_booking(1, admin), %{cancellation_reason: "Jag är sjuk."}, actor: admin)

      assert registration.cancellation_emailed_to == "ada@example.com"
      [job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendCancelledEmail)
      assert :ok = perform_job(Edenflowers.Payments.Workers.SendCancelledEmail, job.args)

      Swoosh.TestAssertions.assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.text_body =~ "Jag är sjuk."
      end)

      {:ok, quiet} = Courses.cancel_registration(paid_booking(1, admin), %{email_customer?: false}, actor: admin)
      assert quiet.cancellation_emailed_to == nil
      assert [_only_the_first] = all_enqueued(worker: Edenflowers.Payments.Workers.SendCancelledEmail)
    end
  end

  describe "revising a checkout" do
    defp revise(registration, params), do: Courses.revise_registration(registration, params, actor: nil)

    defp complete(registration, amount_received) do
      Edenflowers.Payments.complete(%{
        id: registration.payment_intent_id,
        metadata: %{"course_registration_id" => registration.id},
        amount_received: amount_received
      })
    end

    test "keeps the registration and reprices it" do
      {:ok, registration} = register(generate(course(price: "85.00")), 1)

      assert {:ok, revised} = revise(registration, %{name: "Grace Hopper", email: "grace@example.com", seats: 2})

      assert revised.id == registration.id
      assert revised.reference == registration.reference
      assert Decimal.eq?(revised.amount, "170.00")
      assert revised.user_id != registration.user_id
    end

    test "a payment landing after the revision books the revised places" do
      {:ok, registration} = register(generate(course(price: "85.00")), 1)
      registration = Courses.add_registration_payment_intent_id!(registration, "pi_revised", authorize?: false)
      {:ok, _revised} = revise(registration, %{seats: 2})

      ExUnit.CaptureLog.capture_log(fn -> assert {:ok, :completed} = complete(registration, 8_500) end)

      assert %{status: :confirmed, seats: 2} = Courses.get_registration_by_id!(registration.id, authorize?: false)
    end

    test "a revision landing after the payment changes nothing" do
      {:ok, registration} = register(generate(course(price: "85.00")), 1)
      registration = Courses.add_registration_payment_intent_id!(registration, "pi_paid", authorize?: false)
      assert {:ok, :completed} = complete(registration, 8_500)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} =
               revise(registration, %{seats: 2})

      assert %{status: :confirmed, seats: 1} = Courses.get_registration_by_id!(registration.id, authorize?: false)
    end

    test "can't touch an invite, which Jennie changes" do
      {:ok, invite} = add_manually(generate(course()), 1, generate(admin_user()))

      assert {:error, _stale} = revise(invite, %{seats: 2})
    end
  end

  describe "retaining an unfinished checkout" do
    test "old pending registrations have no destructive action and hold no places" do
      course = generate(course())
      yesterday = DateTime.add(DateTime.utc_now(), -25, :hour)
      abandoned = generate(course_registration(course_id: course.id, updated_at: yesterday))
      fresh = generate(course_registration(course_id: course.id))

      invite =
        generate(course_registration(course_id: course.id, payment_link_token: "invite-token", updated_at: yesterday))

      refute Enum.any?(Ash.Resource.Info.actions(Edenflowers.Courses.CourseRegistration), &(&1.type == :destroy))

      system = Edenflowers.Actors.system_actor()
      assert {:ok, _} = Courses.get_registration_by_id(abandoned.id, actor: system)
      assert {:ok, _} = Courses.get_registration_by_id(fresh.id, actor: system)
      assert {:ok, _} = Courses.get_registration_by_id(invite.id, actor: system)
      assert seats_left(course) == course.total_places
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
