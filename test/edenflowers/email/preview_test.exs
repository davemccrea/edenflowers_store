defmodule Edenflowers.Email.PreviewTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Courses.CourseRegistration.Changes.SendReminderEmail
  alias Edenflowers.Email.Preview

  for kind <- [:order, :gift_voucher, :booking], locale <- ["en-GB", "sv-FI", "fi"] do
    @kind kind
    @locale locale
    test "#{@kind} cancellation and in-person refund emails match their actions in #{@locale}" do
      admin = generate(admin_user())

      record =
        case @kind do
          :order ->
            placed_order(locale: @locale, payment_intent_id: nil)

          :gift_voucher ->
            Edenflowers.Orders.sell_gift_voucher!(
              %{customer_name: "Anna", customer_email: "a@example.com", amount: 50, locale: @locale},
              actor: admin
            )

          :booking ->
            generate(course_registration(status: :confirmed, locale: @locale))
        end

      record = Ash.update!(record, %{amount: "50.00", payment_method: :cash}, action: :record_payment, actor: admin)
      preview = Preview.build(:cancelled, record, %{charge: "5.00"})
      cancelled = Ash.update!(record, %{cancellation_charge: "5.00"}, action: :cancel, actor: admin)

      [job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendCancelledEmail)
      assert job.args["to_return"] == "45.00"
      assert job.args["refunded_amount"] == "0"
      assert :ok = perform_job(Edenflowers.Payments.Workers.SendCancelledEmail, job.args)

      assert_email_sent(fn email ->
        assert email.subject == preview.subject
        assert email.text_body == preview.text_body
      end)

      preview = Preview.build(:refunded, cancelled, %{refund: "20.00", payment_method: :cash})
      refunded = Ash.update!(cancelled, %{amount: "20.00", payment_method: :cash}, action: :refund, actor: admin)
      assert Decimal.eq?(refunded.balance, "-25.00")

      [job] = all_enqueued(worker: Edenflowers.Payments.Workers.SendRefundedEmail)
      assert :ok = perform_job(Edenflowers.Payments.Workers.SendRefundedEmail, job.args)

      assert_email_sent(fn email ->
        assert email.subject == preview.subject
        assert email.text_body == preview.text_body
      end)
    end
  end

  for parent <- [:order, :booking], method <- Edenflowers.Payments.PaymentMethod.values() do
    @parent parent
    @method method
    test "the #{@parent} refund preview agrees with the sent email for #{@method} selected as text" do
      record =
        case @parent do
          :order -> placed_order(paid: true)
          :booking -> generate(course_registration(status: :confirmed, locale: "en-GB"))
        end

      form = Phoenix.Component.to_form(%{"amount" => "20.00", "payment_method" => to_string(@method)})
      preview = EdenflowersWeb.Admin.DrawerPreview.build(:refunded, record, form)

      args = %{
        to_string(Edenflowers.Payments.parent_key(record)) => record.id,
        "amount" => "20.00",
        "payment_method" => to_string(@method)
      }

      assert :ok = perform_job(Edenflowers.Payments.Workers.SendRefundedEmail, args)

      assert_email_sent(fn email ->
        assert email.subject == preview.subject
        assert email.text_body == preview.text_body
      end)
    end
  end

  for amount <- [nil, "25.00", "85.00"] do
    @tag :typst
    test "manual confirmation preview matches actual delivery with #{inspect(amount)} received" do
      admin = generate(admin_user())
      course = generate(course())

      input = %{
        name: "Ada",
        email: "ada@example.com",
        course_id: course.id,
        seats: 1,
        locale: "en-GB",
        email_customer?: false
      }

      input =
        if unquote(amount),
          do: Map.merge(input, %{amount: unquote(amount), payment_method: :cash}),
          else: input

      changeset = Ash.Changeset.for_create(CourseRegistration, :add_manually, input, actor: admin)
      preview = Preview.build_entered_booking(changeset, course)
      registration = Ash.create!(changeset)

      assert {:ok, sent} =
               Courses.email_registration_confirmation(registration, actor: admin)

      assert_email_sent(fn email ->
        assert email.text_body == preview.text_body
        assert length(email.attachments) == length(preview.attachments)
        assert length(email.attachments) == if(unquote(amount), do: 1, else: 0)
      end)

      assert sent.confirmation_emailed_at
      assert not is_nil(sent.receipt_emailed_at) == not is_nil(unquote(amount))
      refute sent.payment_link_token
    end
  end

  test "a course payment receipt preview can use the latest actual payment" do
    registration = generate(course_registration(status: :confirmed))
    generate(payment(course_registration_id: registration.id, amount: Decimal.new("30.00"), method: :cash))
    preview = Preview.build(:receipt, registration, %{})

    assert preview.text_body =~ "30,00 €"
    assert [_receipt] = preview.attachments
  end

  test "manual payment link confirmation and course reminder agree with the selected terms" do
    admin = generate(admin_user())
    course = generate(course())

    changeset =
      Ash.Changeset.for_create(
        CourseRegistration,
        :add_manually,
        %{
          name: "Ada",
          email: "ada@example.com",
          course_id: course.id,
          locale: "en-GB",
          payment_terms: :payment_link,
          email_customer?: false
        },
        actor: admin
      )

    preview = Preview.build_entered_booking(changeset, course)
    registration = Ash.create!(changeset)

    expected =
      String.replace(
        preview.text_body,
        "/pay/courses/#{Edenflowers.Email.Edits.placeholder_token()}",
        "/pay/courses/#{registration.payment_link_token}"
      )

    assert {:ok, _sent} = Courses.email_registration_confirmation(registration, %{}, actor: admin)
    assert_email_sent(fn email -> assert email.text_body == expected end)

    # Jennie's rewrite starts from the preview, so it gets the link saving opened.
    edits = %{body: "Lovely to have you.\n\n" <> preview.text_body}
    assert {:ok, _sent} = Courses.email_registration_confirmation(registration, edits, actor: admin)

    assert_email_sent(fn email ->
      assert email.text_body == String.trim_trailing("Lovely to have you.\n\n" <> expected)
    end)

    reminder = reminder(registration)
    refute reminder.text_body =~ "Please pay at the course."
    assert reminder.text_body =~ EdenflowersWeb.PaymentLink.url_for(registration)
  end

  defp reminder(registration) do
    registration
    |> SendReminderEmail.load_for_send()
    |> Edenflowers.Email.course_reminder()
  end
end
