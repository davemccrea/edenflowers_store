defmodule Edenflowers.Payments.InvoicePdfTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Courses.Course
  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Calculations.Vat
  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments
  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Payments.InvoicePdf
  alias Edenflowers.Payments.Payment
  alias Edenflowers.Payments.ReferenceNumber

  @sample_dir Path.join([:code.priv_dir(:edenflowers), "receipts", "sample"])

  describe "build_payload/1" do
    test "has the sample fixtures' shape and labels in every language" do
      for {locale, fixture} <- [
            {"fi", "invoice.fi.json"},
            {"sv-FI", "invoice.sv.json"},
            {"en-GB", "invoice.en.course.json"}
          ] do
        payload = InvoicePdf.payload(frozen(invoice(1000, locale: locale)))
        fixture = read_fixture(fixture)

        assert keys(payload) == keys(fixture)
        assert keys(payload["buyer"]) == keys(fixture["buyer"])
        assert keys(payload["seller"]) == keys(fixture["seller"])
        assert payload["labels"] == fixture["labels"]
      end
    end

    test "a final invoice shows the whole purchase, the invoice before it and what is due on it" do
      booking_fee = invoice(1000, amount: "300.00", invoice_date: ~D[2026-05-15])
      final = invoice(1001, amount: "780.00")
      order = %{wedding() | invoices: [final, booking_fee]}

      payload = InvoicePdf.build_payload(%{final | order: order})

      assert length(payload.line_items) == 2
      assert payload.grand_total == "1\u00A0080,00\u00A0€"
      assert payload.earlier_invoices == [%{number: 1000, invoice_date: "15.5.2026", amount: "−300,00\u00A0€"}]
      assert payload.amount == "780,00\u00A0€"

      assert InvoicePdf.build_payload(%{booking_fee | order: order}).earlier_invoices == []
    end

    test "adds up: what neither this invoice nor earlier ones ask for is left to invoice later" do
      booking_fee = invoice(1000, amount: "300.00")
      order = %{wedding() | invoices: [booking_fee]}

      assert %{label: "invoiced-later", amount: "−780,00" <> _} =
               InvoicePdf.build_payload(%{booking_fee | order: order}).remainder

      second = invoice(1001, amount: "400.00")
      order = %{order | invoices: [booking_fee, second]}

      assert %{label: "invoiced-later", amount: "−380,00" <> _} =
               InvoicePdf.build_payload(%{second | order: order}).remainder

      final = invoice(1002, amount: "380.00")
      order = %{order | invoices: [booking_fee, second, final]}
      assert InvoicePdf.build_payload(%{final | order: order}).remainder == nil
    end

    test "on a cancelled purchase, what isn't charged is shown as not charged" do
      charge = invoice(1000, amount: "300.00")
      order = %{wedding() | cancelled?: true, invoices: [charge]}

      assert %{label: "not-charged", amount: "−780,00" <> _} =
               InvoicePdf.build_payload(%{charge | order: order}).remainder
    end

    test "leaves out an earlier invoice cancelled before this one was made, but not one cancelled after" do
      wrong = invoice(1000, amount: "300.00", credit_note: %CreditNote{number: 1001})
      booking_fee = invoice(1002, amount: "250.00")
      final = invoice(1004, amount: "830.00")
      order = %{wedding() | invoices: [wrong, booking_fee, final]}

      assert [%{number: 1002}] = InvoicePdf.build_payload(%{final | order: order}).earlier_invoices

      cancelled_later = %{wrong | credit_note: %CreditNote{number: 1003}}
      order = %{order | invoices: [cancelled_later, booking_fee]}
      assert [%{number: 1000}] = InvoicePdf.build_payload(%{booking_fee | order: order}).earlier_invoices
    end

    test "a credit note has the sample fixtures' shape and labels, names its invoice and credits its amount" do
      for {locale, fixture} <- [
            {"fi", "credit-note.fi.json"},
            {"sv-FI", "credit-note.sv.json"},
            {"en-GB", "credit-note.en.course.json"}
          ] do
        credited = frozen(invoice(1000, locale: locale, amount: "300.00", invoice_date: ~D[2026-05-15]))
        payload = InvoicePdf.build_payload(%CreditNote{number: 1001, credit_date: ~D[2026-05-18], invoice: credited})
        fixture = read_fixture(fixture)

        assert keys(payload) == keys(fixture)
        assert keys(payload.buyer) == keys(fixture["buyer"])
        assert keys(payload.seller) == keys(fixture["seller"])
        assert payload.labels == fixture["labels"]
        assert payload.invoice_number == 1000
        assert payload.invoice_date == "15.5.2026"
        assert payload.amount == "−300,00 €"
      end
    end

    test "counts money paid outside any invoice before it was made, net of refunds" do
      final = invoice(1001, inserted_at: ~U[2026-06-15 08:00:00Z])

      payments = [
        payment("150.00", ~U[2026-05-01 10:00:00Z]),
        payment("-20.00", ~U[2026-05-02 10:00:00Z]),
        payment("300.00", ~U[2026-05-20 10:00:00Z], invoice_id: Ash.UUID.generate()),
        payment("50.00", ~U[2026-06-16 10:00:00Z])
      ]

      assert InvoicePdf.build_payload(%{final | order: %{wedding() | payments: payments}}).paid_earlier ==
               "−130,00\u00A0€"

      assert InvoicePdf.build_payload(final).paid_earlier == nil
    end

    test "is written in the invoice's language, not the purchase's" do
      invoice = invoice(1000, locale: "fi")
      payload = InvoicePdf.payload(frozen(%{invoice | order: %{wedding() | locale: "sv-FI"}}))

      assert payload["lang"] == "fi"
      assert payload["labels"]["invoice"] == "Lasku"
      assert payload["late_interest_rate"] == "8,00\u00A0%"
    end

    test "is dated with the order's delivery or the course's day, as its date of supply" do
      assert InvoicePdf.build_payload(invoice(1000, locale: "fi")).delivery_date == "13.6.2026"
      assert InvoicePdf.build_payload(invoice(1000, locale: "en-GB")).delivery_date == "28.11.2026"
    end

    test "addresses a company at its billing address and a consumer at their own" do
      company =
        invoice(1000,
          business_customer: true,
          company_name: "Vaasan Juhlatila Oy",
          business_id: "1234567-1",
          billing_address: "Hovioikeudenpuistikko 15 B\n65100 Vaasa",
          buyer_address: "Ignored for a company"
        )

      assert %{company_name: "Vaasan Juhlatila Oy", business_id: "1234567-1", address: "Hovioikeudenpuistikko" <> _} =
               InvoicePdf.build_payload(company).buyer

      assert %{company_name: nil, business_id: nil, address: "Korsholmsesplanaden 12, 65100 Vasa"} =
               InvoicePdf.build_payload(invoice(1000, buyer_address: "Korsholmsesplanaden 12, 65100 Vasa")).buyer
    end

    test "pays the shop's account with the viitenumero, amount and due date through the virtual barcode" do
      payload = InvoicePdf.build_payload(invoice(1001, amount: "780.00", due_date: ~D[2026-06-29]))
      "FI" <> account = String.replace(Invoice.seller().iban, " ", "")

      assert payload.reference_number == "10016"

      assert <<"4", ^account::binary-16, "00078000", "000", "00000000000000010016", "260629">> =
               payload.virtual_barcode
    end
  end

  describe "an invoice's content" do
    test "is frozen when it is made, so editing the order later doesn't change its PDF" do
      admin = generate(admin_user())
      order = placed_order(payment_terms: :invoice, paid: "20.00")
      {:ok, invoice} = Payments.create_invoice(%{order_id: order.id}, actor: admin)
      before = InvoicePdf.payload(invoice)

      variant = generate(product_variant(product_id: generate(product()).id, price: "60.00"))
      generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))

      after_edit = InvoicePdf.payload(Ash.get!(Invoice, invoice.id, authorize?: false))

      assert after_edit == before
      assert [%{"quantity" => 2}] = after_edit["line_items"]
      assert after_edit["grand_total"] == "88,50\u00A0€"
      assert after_edit["paid_earlier"] == "−20,00\u00A0€"
    end

    test "names a booking's course in the invoice's language" do
      admin = generate(admin_user())
      course = generate(course(name: "Autumn Wreaths"))
      Ash.Seed.update!(course, %{translations: %{"fi" => %{"name" => "Syksyiset kranssit"}}})

      registration =
        generate(
          course_registration(course_id: course.id, status: :confirmed, payment_terms: :invoice, locale: "en-GB")
        )

      {:ok, invoice} = Payments.create_invoice(%{course_registration_id: registration.id, locale: "fi"}, actor: admin)

      assert [%{"product_name" => "Syksyiset kranssit"}] = invoice.content["line_items"]
    end
  end

  describe "generate/1" do
    @describetag :typst

    test "renders a PDF for an order's invoice and a Course booking's in every language" do
      admin = generate(admin_user())
      order = placed_order(payment_terms: :invoice, locale: "fi")
      registration = generate(course_registration(status: :confirmed, payment_terms: :invoice))

      {:ok, _booking_fee} = Payments.create_invoice(%{order_id: order.id, amount: "30.00"}, actor: admin)
      {:ok, _} = Orders.update_order_business_details(order, company(), actor: admin)

      for {purchase, locale} <- [
            {%{order_id: order.id}, "sv-FI"},
            {%{course_registration_id: registration.id}, "en-GB"}
          ] do
        {:ok, invoice} = Payments.create_invoice(Map.put(purchase, :locale, locale), actor: admin)
        assert {:ok, <<"%PDF-", _::binary>>} = InvoicePdf.generate(invoice)
      end

      {:ok, invoice} = Payments.create_invoice(%{order_id: order.id, amount: "5.00"}, actor: admin)
      assert {:ok, <<"%PDF-", _::binary>>} = InvoicePdf.generate(invoice)
    end
  end

  # What creating the invoice would have frozen onto it.
  defp frozen(invoice),
    do: %{invoice | content: invoice |> InvoicePdf.build_payload() |> Jason.encode!() |> Jason.decode!()}

  defp company do
    %{business_customer: true, company_name: "Kukka Oy", business_id: "2944459-6", billing_address: "Kyrkvägen 5"}
  end

  defp invoice(number, attrs) do
    struct!(
      %Invoice{
        number: number,
        reference_number: ReferenceNumber.from_invoice_number(number),
        locale: "fi",
        amount: Decimal.new("780.00"),
        invoice_date: ~D[2026-06-15],
        due_date: ~D[2026-06-29],
        inserted_at: ~U[2026-06-15 08:00:00Z],
        buyer_name: "Emilia Virtanen",
        buyer_email: "emilia@example.fi",
        buyer_address: nil,
        business_customer: false,
        customer_reference: nil,
        order: wedding(),
        course_registration: nil
      },
      Enum.map(attrs, fn
        {:amount, amount} -> {:amount, Decimal.new(amount)}
        attr -> attr
      end)
    )
    |> course_for_english()
  end

  # The English sample is a Course booking, so the payloads compared with it
  # need a booking's shape.
  defp course_for_english(%Invoice{locale: "en-GB"} = invoice) do
    %{invoice | order: nil, course_registration: advent_wreaths()}
  end

  defp course_for_english(invoice), do: invoice

  defp wedding do
    lines = [line_item("Morsiuskimppu", "180.00", 1), line_item("Pöytäkoristeet", "45.00", 19)]
    items = lines |> Enum.map(& &1.total) |> Enum.reduce(&Decimal.add/2)
    fee = Decimal.new("45.00")

    %Order{
      locale: "fi",
      order_reference: "1530",
      ordered_at: ~U[2026-04-20 09:12:00Z],
      customer_name: "Emilia Virtanen",
      customer_email: "emilia@example.fi",
      fulfillment_method: :delivery,
      fulfillment_date: ~D[2026-06-13],
      fulfillment_fee: fee,
      fulfillment_tax_rate: Decimal.new("0.255"),
      promotion_applied?: false,
      discount: Decimal.new(0),
      items_subtotal: items,
      items_total: items,
      grand_total: Decimal.add(items, fee),
      line_items: lines,
      upcoming?: false,
      cancelled?: false,
      payments: [],
      invoices: []
    }
  end

  defp advent_wreaths do
    %CourseRegistration{
      locale: "en-GB",
      reference: "C-1612",
      name: "Sarah Mills",
      email: "sarah.mills@example.com",
      seats: 2,
      amount: Decimal.new("170.00"),
      tax_rate: Decimal.new("0.255"),
      confirmed_at: ~U[2026-10-30 15:40:00Z],
      upcoming?: true,
      cancelled?: false,
      payments: [],
      invoices: [],
      course: %Course{
        name: "Advent Wreaths",
        date: ~D[2026-11-28],
        start_time: ~T[10:00:00],
        end_time: ~T[14:00:00],
        location_name: "Minimossen",
        location_address: "Myrvägen 1, 65230 Vasa"
      }
    }
  end

  defp line_item(name, price, quantity) do
    price = Decimal.new(price)
    rate = Decimal.new("0.255")
    total = Decimal.mult(price, quantity)

    %LineItem{
      product_name: name,
      quantity: quantity,
      unit_price_ex_tax: Vat.net_of_vat(price, rate),
      tax_rate: rate,
      subtotal: total,
      total: total
    }
  end

  defp payment(amount, paid_at, attrs \\ []) do
    struct!(%Payment{amount: Decimal.new(amount), paid_at: paid_at, invoice_id: nil}, attrs)
  end

  defp keys(map), do: map |> Map.keys() |> MapSet.new(&to_string/1)

  defp read_fixture(name), do: @sample_dir |> Path.join(name) |> File.read!() |> Jason.decode!()
end
