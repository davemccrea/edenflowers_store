defmodule Edenflowers.Courses.PaymentLinkTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.Courses
  alias Edenflowers.Courses.Course
  alias Edenflowers.Email.Preview
  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Payments

  setup :verify_on_exit!

  setup do
    admin = generate(admin_user())

    {:ok, registration} =
      Courses.add_registration_manually(
        %{name: "Ada Lovelace", email: "ada@example.com", seats: 1, course_id: generate(course()).id, locale: "fi"},
        actor: admin
      )

    %{admin: admin, registration: registration}
  end

  defp reload(registration) do
    Courses.get_registration_by_id!(registration.id,
      authorize?: false,
      load: [:balance, :settled?, :payment_link_open?, :payments]
    )
  end

  defp pay_in_person(registration, amount) do
    generate(payment(course_registration_id: registration.id, method: :cash, amount: Decimal.new(amount)))
    registration
  end

  defp link_intent(registration, id, amount_received) do
    %{id: id, metadata: %{"course_registration_id" => registration.id}, amount_received: amount_received}
  end

  describe "opening a payment link" do
    test "gives a booking owing money a token, and keeps it when opened again", ctx do
      {:ok, opened} = Courses.open_registration_payment_link(ctx.registration, actor: ctx.admin)
      assert is_binary(opened.payment_link_token)
      assert reload(opened).payment_link_open?

      {:ok, reopened} = Courses.open_registration_payment_link(opened, actor: ctx.admin)
      assert reopened.payment_link_token == opened.payment_link_token
    end

    test "is refused for customers", ctx do
      assert {:error, %Ash.Error.Forbidden{}} = Courses.open_registration_payment_link(ctx.registration, actor: nil)
    end

    test "a cancelled or settled booking has no open link", ctx do
      {:ok, opened} = Courses.open_registration_payment_link(ctx.registration, actor: ctx.admin)
      pay_in_person(opened, "85.00")
      refute reload(opened).payment_link_open?

      other = generate(course_registration(status: :confirmed))
      {:ok, other} = Courses.open_registration_payment_link(other, actor: ctx.admin)
      {:ok, _cancelled} = Courses.cancel_registration(other, actor: ctx.admin)
      refute reload(other).payment_link_open?
    end
  end

  test "a PaymentIntent for a booking with part paid is for the balance", ctx do
    pay_in_person(ctx.registration, "30.00")
    registration_id = ctx.registration.id

    expect(StripeAPI.Mock, :create_payment_intent, fn 5500, %{"course_registration_id" => ^registration_id}, nil ->
      {:ok, %{id: "pi_link", client_secret: "pi_link_secret", amount: 5500}}
    end)

    assert {:ok, _registration, "pi_link_secret"} = Payments.setup(reload(ctx.registration), nil)
  end

  describe "paying through the link" do
    test "books an invite's places, records the Stripe payment and emails the confirmation", ctx do
      registration = Ash.Seed.update!(ctx.registration, %{payment_intent_id: "pi_link"})

      assert registration.status == :pending
      assert {:ok, :completed} = Payments.complete(link_intent(registration, "pi_link", 8500))

      paid = reload(registration)
      assert paid.status == :confirmed
      assert paid.confirmed_at
      assert paid.settled?
      assert paid.payment_intent_id == nil
      assert [%{method: :stripe, payment_intent_id: "pi_link"}] = paid.payments

      assert_enqueued(
        worker: Edenflowers.Courses.Workers.SendConfirmationEmail,
        args: %{"primary_key" => %{"id" => registration.id}}
      )
    end

    test "books an invite even once the course has filled up", ctx do
      course =
        Course |> Ash.get!(ctx.registration.course_id, authorize?: false) |> Ash.Seed.update!(%{total_places: 2})

      generate(course_registration(course_id: course.id, seats: 2, status: :confirmed))
      registration = Ash.Seed.update!(ctx.registration, %{payment_intent_id: "pi_link"})

      assert {:ok, :completed} = Payments.complete(link_intent(registration, "pi_link", 8500))
      assert reload(registration).status == :confirmed
    end

    test "pays a balance left on a confirmed booking and emails Payment received", ctx do
      registration =
        ctx.registration
        |> Ash.Seed.update!(%{status: :confirmed, payment_intent_id: "pi_link"})
        |> pay_in_person("30.00")

      assert {:ok, :completed} = Payments.complete(link_intent(registration, "pi_link", 5500))
      assert reload(registration).settled?

      assert_enqueued(
        worker: Edenflowers.Courses.Workers.SendPaymentReceivedEmail,
        args: %{"primary_key" => %{"id" => registration.id}}
      )
    end

    test "records the payment once, however often it is delivered", ctx do
      registration = Ash.Seed.update!(ctx.registration, %{payment_intent_id: "pi_link"})

      assert {:ok, :completed} = Payments.complete(link_intent(registration, "pi_link", 8500))
      assert {:ok, :already_completed} = Payments.complete(link_intent(registration, "pi_link", 8500))

      assert [_one] = reload(registration).payments
    end
  end

  describe "a payment reminder" do
    test "opens the link if need be and asks a confirmed booking for what's still owed", ctx do
      confirmed =
        ctx.registration
        |> Ash.Seed.update!(%{status: :confirmed, payment_link_token: nil})
        |> pay_in_person("30.00")

      {:ok, reminded} =
        Courses.send_registration_payment_reminder(confirmed, %{message: "See you soon."}, actor: ctx.admin)

      assert reload(reminded).payment_link_open?

      assert_email_sent(fn email ->
        assert email.text_body =~ "See you soon."
        assert email.text_body =~ EdenflowersWeb.PaymentLink.url_for(reload(reminded))
      end)
    end
  end

  describe "emailing the link" do
    test "a future confirmed booking gets a Payment reminder matching its preview", ctx do
      confirmed =
        ctx.registration
        |> Ash.Seed.update!(%{status: :confirmed})
        |> pay_in_person("30.00")

      preview = Preview.build(:payment_link, confirmed, %{message: "See you soon."})

      {:ok, _emailed} =
        Courses.email_registration_payment_link(confirmed, %{message: "See you soon."}, actor: ctx.admin)

      assert_email_sent(fn email ->
        assert email.subject == preview.subject
        assert email.text_body == preview.text_body
        refute email.text_body =~ "Paikkasi varataan heti, kun olet maksanut."
        assert email.text_body =~ "55,00"
      end)
    end

    test "opens the link and sends one email in the booking's language", ctx do
      preview = Preview.build(:payment_link, ctx.registration, %{})
      {:ok, emailed} = Courses.email_registration_payment_link(ctx.registration, actor: ctx.admin)

      assert emailed.payment_link_emailed_at
      assert reload(emailed).payment_link_open?

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.subject =~ "Varaa paikkasi kurssille"
        assert email.text_body == preview.text_body
        assert email.text_body =~ "Paikkasi varataan heti, kun olet maksanut."
        refute email.text_body =~ "palautan koko summan"
        assert email.text_body =~ "/pay/courses/#{emailed.payment_link_token}"
        assert email.text_body =~ "85,00"
      end)

      refute_email_sent()
    end

    test "after the course, leaves out paying at the course and cancelling", ctx do
      Course
      |> Ash.get!(ctx.registration.course_id, authorize?: false)
      |> Ash.Seed.update!(%{date: Date.add(Edenflowers.ShopTime.today(), -1)})

      {:ok, _emailed} = Courses.email_registration_payment_link(ctx.registration, actor: ctx.admin)

      assert_email_sent(fn email ->
        refute email.text_body =~ "Voit myös maksaa kurssilla"
        refute email.text_body =~ "perua varauksen"
        refute email.text_body =~ "Nähdään,"
        assert email.text_body =~ "Lämpimin terveisin,"
      end)
    end

    test "is refused once nothing is owed", ctx do
      paid = pay_in_person(ctx.registration, "85.00")

      assert {:error, _} = Courses.email_registration_payment_link(paid, actor: ctx.admin)
      refute_email_sent()
    end
  end
end
