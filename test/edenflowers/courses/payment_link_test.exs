defmodule Edenflowers.Courses.PaymentLinkTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox
  import Swoosh.TestAssertions

  alias Edenflowers.Courses
  alias Edenflowers.Courses.Workers.SendConfirmationEmail
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

  defp link_intent(registration, id, amount_received) do
    %{id: id, metadata: %{"course_registration_id" => registration.id}, amount_received: amount_received}
  end

  describe "opening a payment link" do
    test "gives a confirmed booking owing money a token, and keeps it when opened again", ctx do
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
      {:ok, _paid} = Courses.record_registration_payment(opened, "85.00", :cash, actor: ctx.admin)
      refute reload(opened).payment_link_open?

      other = generate(course_registration(status: :confirmed))
      {:ok, other} = Courses.open_registration_payment_link(other, actor: ctx.admin)
      {:ok, _cancelled} = Courses.cancel_registration(other, actor: ctx.admin)
      refute reload(other).payment_link_open?
    end
  end

  test "a PaymentIntent for a booking with part paid is for the balance", ctx do
    {:ok, _paid} = Courses.record_registration_payment(ctx.registration, "30.00", :cash, actor: ctx.admin)
    registration_id = ctx.registration.id

    expect(StripeAPI.Mock, :create_payment_intent, fn 5500, %{"course_registration_id" => ^registration_id}, nil ->
      {:ok, %{id: "pi_link", client_secret: "pi_link_secret", amount: 5500}}
    end)

    assert {:ok, _registration, "pi_link_secret"} = Payments.setup(reload(ctx.registration), nil)
  end

  describe "paying through the link" do
    test "records a Stripe payment on the confirmed booking, settles it and emails the receipt", ctx do
      registration =
        Ash.Seed.update!(ctx.registration, %{payment_intent_id: "pi_link", confirmation_emailed_at: DateTime.utc_now()})

      assert {:ok, :completed} = Payments.complete(link_intent(registration, "pi_link", 8500))

      paid = reload(registration)
      assert paid.status == :confirmed
      assert paid.settled?
      assert paid.payment_intent_id == nil
      assert paid.confirmation_emailed_at == nil
      assert [%{method: :stripe, payment_intent_id: "pi_link"}] = paid.payments
      assert_enqueued(worker: SendConfirmationEmail, args: %{"primary_key" => %{"id" => registration.id}})
    end

    test "records the payment once, however often it is delivered", ctx do
      registration = Ash.Seed.update!(ctx.registration, %{payment_intent_id: "pi_link"})

      assert {:ok, :completed} = Payments.complete(link_intent(registration, "pi_link", 8500))
      assert {:ok, :already_completed} = Payments.complete(link_intent(registration, "pi_link", 8500))

      assert [_one] = reload(registration).payments
    end

    test "a pending booking's checkout still confirms it" do
      registration = generate(course_registration(status: :pending, payment_intent_id: "pi_checkout"))

      assert {:ok, :completed} = Payments.complete(link_intent(registration, "pi_checkout", 8500))

      assert reload(registration).status == :confirmed
    end

    test "recording a payment by hand cancels the link's open PaymentIntent", ctx do
      registration = Ash.Seed.update!(ctx.registration, %{payment_intent_id: "pi_link"})

      expect(StripeAPI.Mock, :cancel_payment_intent, fn %{id: "pi_link"} -> {:ok, %{id: "pi_link"}} end)

      {:ok, _paid} = Courses.record_registration_payment(registration, "85.00", :zettle, actor: ctx.admin)

      assert reload(registration).payment_intent_id == nil
    end
  end

  describe "emailing the link" do
    test "opens the link and sends one email in the booking's language", ctx do
      {:ok, emailed} = Courses.email_registration_payment_link(ctx.registration, actor: ctx.admin)

      assert emailed.payment_link_emailed_at
      assert reload(emailed).payment_link_open?

      assert_email_sent(fn email ->
        assert email.to == [{"", "ada@example.com"}]
        assert email.subject =~ "Maksa varauksesi kurssille"
        assert email.text_body =~ "maksettavaa kurssista"
        refute email.text_body =~ "palautan koko summan"
        assert email.text_body =~ "/courses/pay/#{emailed.payment_link_token}"
        assert email.text_body =~ "85,00"
      end)

      refute_email_sent()
    end

    test "is refused once nothing is owed", ctx do
      {:ok, paid} = Courses.record_registration_payment(ctx.registration, "85.00", :cash, actor: ctx.admin)

      assert {:error, _} = Courses.email_registration_payment_link(paid, actor: ctx.admin)
      refute_email_sent()
    end
  end
end
