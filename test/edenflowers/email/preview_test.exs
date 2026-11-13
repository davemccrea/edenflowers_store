defmodule Edenflowers.Email.PreviewTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Courses
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Courses.CourseRegistration.Changes.SendReminderEmail
  alias Edenflowers.Email.Edits
  alias Edenflowers.Email.Preview
  alias Edenflowers.Orders

  # Every email Jennie sends by hand, as `{scenario, options}`. Each scenario
  # builds the preview she reads first, then sends as her drawer or form does.
  # `typst: true` makes a receipt PDF.
  @hand_sent [
    {:order_details, []},
    {:order_details_with_open_link, []},
    {:entered_order_details, []},
    {:entered_order_updated, []},
    {:order_payment_reminder_opening_link, []},
    {:order_payment_reminder_with_open_link, []},
    {:order_receipt, [typst: true]},
    {:order_payment, [typst: true]},
    {:order_part_payment, [typst: true]},
    {:gift_voucher, [typst: true]},
    {:gift_voucher_payment, [typst: true]},
    {:delivered, []},
    {:left_at_door, []},
    {:left_at_door_on_handover, []},
    {:booking_confirmation_unpaid, []},
    {:booking_confirmation_paid, [typst: true]},
    {:booking_confirmation_with_open_link, []},
    {:booking_payment_reminder_opening_link, []},
    {:booking_payment_link, []},
    {:booking_payment_link_already_open, []},
    {:booking_course_reminder, []},
    {:booking_payment, [typst: true]},
    {:booking_part_payment, [typst: true]}
  ]

  describe "the preview is the email sent" do
    for {scenario, options} <- @hand_sent, locale <- ["en-GB", "sv-FI", "fi"] do
      @tag typst: Keyword.get(options, :typst, false)
      test "#{scenario} in #{locale}" do
        admin = generate(admin_user())
        %{preview: preview, send: send} = hand_sent(unquote(scenario), unquote(locale), admin)
        sent_record = send.()

        assert_email_sent(fn email ->
          assert email.subject == preview.subject
          assert email.to == preview.to
          assert email.text_body == with_link_opened(preview.text_body, sent_record)
          assert email.html_body == preview.html_body
          assert attachment_names(email) == attachment_names(preview)
        end)
      end
    end
  end

  # A link that sending opens shows a placeholder until then (ADR 0006).
  defp with_link_opened(body, %{payment_link_token: token}) when is_binary(token),
    do: String.replace(body, Edits.placeholder_token(), token)

  defp with_link_opened(body, _record), do: body

  defp attachment_names(email), do: Enum.map(email.attachments, & &1.filename)

  defp hand_sent(:order_details, locale, admin) do
    order = placed_order(locale: locale, payment_intent_id: nil)

    %{
      preview: Preview.build(:order_details, order, %{}),
      send: fn -> Orders.send_order_details_email!(order, actor: admin) end
    }
  end

  defp hand_sent(:order_details_with_open_link, locale, admin) do
    order = placed_order(locale: locale, payment_intent_id: nil) |> Orders.open_payment_link!(actor: admin)

    %{
      preview: Preview.build(:order_details, order, %{}),
      send: fn -> Orders.send_order_details_email!(order, actor: admin) end
    }
  end

  defp hand_sent(:entered_order_details, locale, admin) do
    params = entered_order_params(locale)
    changeset = Ash.Changeset.for_create(Orders.Order, :place_custom, params, actor: admin)
    price = Orders.quote_entered_order!(nil, params, nil, actor: admin)

    %{
      preview: Preview.build_entered(:order_details, changeset, price, nil),
      send: fn -> changeset |> Ash.create!() |> deliver_queued(Orders.Workers.SendOrderDetailsEmail) end
    }
  end

  defp hand_sent(:entered_order_updated, locale, admin) do
    placed = entered_order_params(locale)

    order =
      placed
      |> Map.put("email_customer?", "false")
      |> Orders.place_custom_order!(actor: admin)
      |> Ash.load!(:payment_link_open?, authorize?: false)

    params = placed |> put_in(["line_items", Access.at(0), "quantity"], "3") |> Map.put("email_customer?", "true")
    changeset = Ash.Changeset.for_update(order, :edit, params, actor: admin)
    price = Orders.quote_entered_order!(order, params, nil, actor: admin)

    %{
      preview: Preview.build_entered(:order_updated, changeset, price, order),
      send: fn -> changeset |> Ash.update!() |> deliver_queued(Orders.Workers.SendOrderUpdatedEmail) end
    }
  end

  defp hand_sent(:order_payment_reminder_opening_link, locale, admin) do
    order = placed_order(locale: locale, payment_intent_id: nil)

    %{
      preview: Preview.build(:payment_reminder, order, %{}),
      send: fn -> Orders.send_payment_reminder!(order, actor: admin) end
    }
  end

  defp hand_sent(:order_payment_reminder_with_open_link, locale, admin) do
    order =
      placed_order(locale: locale, payment_intent_id: nil, paid: "40.00") |> Orders.open_payment_link!(actor: admin)

    %{
      preview: Preview.build(:payment_reminder, order, %{}),
      send: fn -> Orders.send_payment_reminder!(order, actor: admin) end
    }
  end

  defp hand_sent(:order_receipt, locale, admin) do
    order = placed_order(locale: locale, paid: true)
    %{preview: Preview.build(:receipt, order, %{}), send: fn -> Orders.email_receipt!(order, actor: admin) end}
  end

  defp hand_sent(:order_payment, locale, admin) do
    order = placed_order(locale: locale, payment_intent_id: nil)

    %{
      preview: Preview.build(:receipt, order, %{amount: "88.50"}),
      send: fn -> Orders.record_payment!(order, "88.50", :cash, %{email_receipt?: true}, actor: admin) end
    }
  end

  defp hand_sent(:order_part_payment, locale, admin) do
    order = placed_order(locale: locale, payment_intent_id: nil, paid: "40.00")

    %{
      preview: Preview.build(:receipt, order, %{amount: "20.00"}),
      send: fn -> Orders.record_payment!(order, "20.00", :cash, %{email_receipt?: true}, actor: admin) end
    }
  end

  defp hand_sent(:gift_voucher, locale, admin) do
    sale = locale |> gift_voucher_sale(admin) |> Orders.record_payment!("50.00", :cash, actor: admin)
    %{preview: Preview.build(:gift_voucher, sale, %{}), send: fn -> Orders.email_gift_voucher!(sale, actor: admin) end}
  end

  defp hand_sent(:gift_voucher_payment, locale, admin) do
    sale = gift_voucher_sale(locale, admin)

    %{
      preview: Preview.build(:receipt, sale, %{amount: "50.00"}),
      send: fn -> Orders.record_payment!(sale, "50.00", :cash, %{email_receipt?: true}, actor: admin) end
    }
  end

  defp hand_sent(:delivered, locale, admin) do
    order = delivery_order(locale, fulfillment_status: :fulfilled)

    %{
      preview: Preview.build(:fulfillment, order, %{}),
      send: fn ->
        order
        |> Orders.email_fulfillment_confirmation!(actor: admin)
        |> deliver_queued(Orders.Workers.SendFulfillmentEmail)
      end
    }
  end

  defp hand_sent(:left_at_door, locale, admin) do
    stub_delivery_photo()

    order =
      delivery_order(locale,
        fulfillment_status: :fulfilled,
        delivery_photo_slug: "local:///uploads/door.jpg",
        email_delivery_photo: true
      )

    %{
      preview: Preview.build(:fulfillment, order, %{}),
      send: fn ->
        order
        |> Orders.email_fulfillment_confirmation!(actor: admin)
        |> deliver_queued(Orders.Workers.SendFulfillmentEmail)
      end
    }
  end

  defp hand_sent(:left_at_door_on_handover, locale, admin) do
    stub_delivery_photo()
    order = delivery_order(locale, fulfillment_status: :ready)

    %{
      preview: Preview.build(:fulfillment, order, %{photo?: true}),
      send: fn ->
        order
        |> Orders.mark_order_fulfilled!(
          %{delivery_photo_slug: "local:///uploads/door.jpg", email_delivery_photo: true},
          actor: admin
        )
        |> deliver_queued(Orders.Workers.SendFulfillmentEmail)
      end
    }
  end

  defp hand_sent(:booking_confirmation_unpaid, locale, admin) do
    registration = generate(course_registration(status: :confirmed, locale: locale))

    %{
      preview: Preview.build(:confirmation, registration, %{}),
      send: fn -> Courses.email_registration_confirmation!(registration, actor: admin) end
    }
  end

  defp hand_sent(:booking_confirmation_paid, locale, admin) do
    registration = generate(course_registration(status: :confirmed, locale: locale))
    generate(payment(course_registration_id: registration.id, amount: Decimal.new("85.00"), method: :cash))

    %{
      preview: Preview.build(:confirmation, registration, %{}),
      send: fn -> Courses.email_registration_confirmation!(registration, actor: admin) end
    }
  end

  defp hand_sent(:booking_confirmation_with_open_link, locale, admin) do
    registration =
      generate(course_registration(status: :confirmed, locale: locale))
      |> Courses.open_registration_payment_link!(actor: admin)

    %{
      preview: Preview.build(:confirmation, registration, %{}),
      send: fn -> Courses.email_registration_confirmation!(registration, actor: admin) end
    }
  end

  defp hand_sent(:booking_payment_reminder_opening_link, locale, admin) do
    registration = generate(course_registration(status: :confirmed, locale: locale))
    generate(payment(course_registration_id: registration.id, amount: Decimal.new("30.00"), method: :cash))

    %{
      preview: Preview.build(:payment_reminder, registration, %{}),
      send: fn -> Courses.send_registration_payment_reminder!(registration, actor: admin) end
    }
  end

  defp hand_sent(:booking_payment_link, locale, admin) do
    registration = generate(course_registration(status: :confirmed, locale: locale))

    %{
      preview: Preview.build(:payment_link, registration, %{}),
      send: fn -> Courses.email_registration_payment_link!(registration, actor: admin) end
    }
  end

  defp hand_sent(:booking_payment_link_already_open, locale, admin) do
    registration =
      generate(course_registration(status: :confirmed, locale: locale))
      |> Courses.open_registration_payment_link!(actor: admin)

    %{
      preview: Preview.build(:payment_link, registration, %{}),
      send: fn -> Courses.email_registration_payment_link!(registration, actor: admin) end
    }
  end

  defp hand_sent(:booking_course_reminder, locale, admin) do
    registration = generate(course_registration(status: :confirmed, locale: locale))

    %{
      preview: Preview.build(:course_reminder, registration, %{}),
      send: fn ->
        registration
        |> Ash.update!(%{}, action: :email_course_reminder, actor: admin)
        |> deliver_queued(Courses.Workers.SendReminderEmail)
      end
    }
  end

  defp hand_sent(:booking_payment, locale, admin) do
    registration = generate(course_registration(status: :confirmed, locale: locale))

    %{
      preview: Preview.build(:receipt, registration, %{amount: "85.00"}),
      send: fn ->
        Courses.record_registration_payment!(registration, "85.00", :cash, %{email_receipt?: true}, actor: admin)
      end
    }
  end

  defp hand_sent(:booking_part_payment, locale, admin) do
    registration = generate(course_registration(status: :confirmed, locale: locale))

    %{
      preview: Preview.build(:receipt, registration, %{amount: "30.00"}),
      send: fn ->
        Courses.record_registration_payment!(registration, "30.00", :cash, %{email_receipt?: true}, actor: admin)
      end
    }
  end

  defp deliver_queued(record, worker) do
    [job] = all_enqueued(worker: worker)
    perform_job(worker, job.args)
    record
  end

  defp gift_voucher_sale(locale, admin) do
    Orders.sell_gift_voucher!(
      %{customer_name: "Anna", customer_email: "a@example.com", amount: 50, locale: locale},
      actor: admin
    )
  end

  defp delivery_order(locale, attrs) do
    generate(
      order(
        [
          state: :placed,
          customer_name: "Ada Lovelace",
          customer_email: "ada@example.com",
          fulfillment_method: :delivery,
          fulfillment_date: ~D[2026-06-10],
          locale: locale
        ] ++ attrs
      )
    )
  end

  defp stub_delivery_photo do
    Req.Test.stub(Edenflowers.Orders.Order.Changes.SendFulfillmentEmail, fn conn ->
      Plug.Conn.send_resp(conn, 200, "small jpeg")
    end)
  end

  defp entered_order_params(locale) do
    tax_rate = generate(tax_rate(percentage: "0.255"))
    product = generate(product(tax_rate_id: tax_rate.id, name: "Spring Bouquet"))
    variant = generate(product_variant(product_id: product.id, price: "49.00"))
    pickup = generate(fulfillment_option(tax_rate_id: tax_rate.id, fulfillment_method: :pickup, base_price: "0.00"))

    %{
      "customer_name" => "Mrs Holm",
      "customer_email" => "holm@example.com",
      "locale" => locale,
      "fulfillment_option_id" => pickup.id,
      "fulfillment_date" => Date.to_iso8601(Date.add(Edenflowers.ShopTime.today(), 1)),
      "line_items" => [%{"kind" => "catalogue", "product_variant_id" => variant.id, "quantity" => "1"}]
    }
  end

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

    # The edited body starts from the unsaved preview, which contains a placeholder
    # payment link. Sending must replace it with the saved registration's real link.
    edits = %{body: "Lovely to have you.\n\n" <> preview.text_body}
    assert {:ok, _sent} = Courses.email_registration_confirmation(registration, edits, actor: admin)

    assert_email_sent(fn email ->
      assert email.text_body == String.trim_trailing("Lovely to have you.\n\n" <> expected)
    end)

    reminder = reminder(registration)
    refute reminder.text_body =~ "You can pay when you come to the course."
    assert reminder.text_body =~ EdenflowersWeb.PaymentLink.url_for(registration)
  end

  defp reminder(registration) do
    registration
    |> SendReminderEmail.load_for_send()
    |> Edenflowers.Email.course_reminder()
  end
end
