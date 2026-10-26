defmodule Edenflowers.Email.PreviewTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email.Preview

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
        email_customer?: false,
        message: "See you soon."
      }

      input =
        if unquote(amount),
          do: Map.merge(input, %{amount: unquote(amount), payment_method: :cash}),
          else: input

      changeset = Ash.Changeset.for_create(CourseRegistration, :add_manually, input, actor: admin)
      preview = Preview.build_entered_booking(changeset, course, %{message: input.message})
      registration = Ash.create!(changeset)

      assert {:ok, sent} =
               Courses.email_registration_confirmation(registration, %{message: input.message}, actor: admin)

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

    assert preview.text_body =~ "€30.00"
    assert [_receipt] = preview.attachments
  end

  for terms <- [:invoice, :payment_link] do
    test "manual #{terms} confirmation and course reminder agree with the selected terms" do
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
            payment_terms: unquote(terms),
            email_customer?: false
          },
          actor: admin
        )

      preview = Preview.build_entered_booking(changeset, course, %{})
      registration = Ash.create!(changeset)
      assert {:ok, _sent} = Courses.email_registration_confirmation(registration, %{}, actor: admin)

      expected =
        if unquote(terms) == :payment_link do
          String.replace(preview.text_body, "/pay/courses/preview", "/pay/courses/#{registration.payment_link_token}")
        else
          preview.text_body
        end

      assert_email_sent(fn email -> assert email.text_body == expected end)

      reminder =
        registration
        |> Ash.load!([:course, :first_name, :balance], authorize?: false)
        |> Edenflowers.Email.course_reminder()

      refute reminder.text_body =~ "Please pay at the course."

      if unquote(terms) == :payment_link do
        assert reminder.text_body =~ EdenflowersWeb.PaymentLink.url_for(registration)
      else
        assert reminder.text_body =~ "I'll send you an invoice separately."
        refute reminder.text_body =~ "/pay/courses/"
      end
    end
  end
end
