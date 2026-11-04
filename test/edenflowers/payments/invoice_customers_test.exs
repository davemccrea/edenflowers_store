defmodule Edenflowers.Payments.InvoiceCustomersTest do
  use Edenflowers.DataCase, async: true
  import Generator

  alias Edenflowers.Payments

  setup do
    %{admin: generate(admin_user())}
  end

  defp invoice(admin, attrs, issue? \\ true) do
    base = %{
      buyer_name: "Anna Old",
      buyer_email: "anna@example.com",
      locale: "fi",
      supply_date: ~D[2026-11-02],
      lines: [%{description: "Flowers", quantity: "1", unit_price: "10", vat_rate: "25.5"}]
    }

    {:ok, draft} = Payments.create_invoice(Map.merge(base, attrs), actor: admin)
    if issue?, do: Payments.issue_invoice!(draft, actor: admin), else: draft
  end

  defp shop_customer(name, email, ordered_at) do
    user = generate(admin_user(admin: false, name: name, email: email))
    generate(order(state: :placed, user_id: user.id, ordered_at: ordered_at, locale: "en-GB"))
    user
  end

  defp find(term, admin), do: Payments.find_invoice_customers!(term, actor: admin)

  test "a customer is found by their latest issued invoice only, so an outdated name finds nothing", %{admin: admin} do
    invoice(admin, %{})
    latest = invoice(admin, %{buyer_name: "Anna New", buyer_email: "ANNA@example.com"})
    invoice(admin, %{buyer_name: "Anna Draft"}, false)

    assert [%{id: id, details: details}] = find("anna", admin)
    assert id == latest.id
    assert details.buyer_name == "Anna New"
    assert find("Old", admin) == []
  end

  test "an issued invoice that was never emailed still gives its customer", %{admin: admin} do
    issued = invoice(admin, %{})
    assert issued.sent_at == nil
    assert [%{id: id}] = find("anna", admin)
    assert id == issued.id
  end

  test "a business is a customer of its own beside the same email as a private customer", %{admin: admin} do
    invoice(admin, %{})

    invoice(admin, %{
      business_customer: true,
      company_name: "Kukka Oy",
      business_id: "2944459-6",
      billing_address: "Kauppakatu 1"
    })

    assert [%{buyer: "Kukka Oy", details: %{business_customer: true}}, %{buyer: "Anna Old"}] = find("anna", admin)
    assert [%{buyer: "Kukka Oy"}] = find("kukka", admin)
  end

  test "shop customers come with name, email and their latest order's language, unless already invoiced", %{
    admin: admin
  } do
    invoice(admin, %{})
    shop_customer("Anna Shopper", "Anna@example.com", ~U[2030-01-01 12:00:00Z])
    shop_customer("Ville", "ville@example.com", ~U[2030-01-01 12:00:00Z])

    assert [%{buyer: "Anna Old"}] = find("anna", admin)

    assert [%{buyer: "Ville", details: details}] = find("ville", admin)
    assert %{buyer_email: "ville@example.com", locale: "en-GB", business_customer: false, company_name: nil} = details
  end

  test "without a term, the most recently billed or ordered customers come first, ten at most", %{admin: admin} do
    shop_customer("Earlier Shopper", "earlier@example.com", ~U[2020-01-01 12:00:00Z])
    for n <- 1..10, do: invoice(admin, %{buyer_name: "Customer #{n}", buyer_email: "c#{n}@example.com"})
    shop_customer("Latest Shopper", "latest@example.com", ~U[2030-01-01 12:00:00Z])

    customers = find(nil, admin)
    assert length(customers) == 10
    assert hd(customers).buyer == "Latest Shopper"
    assert Enum.at(customers, 1).buyer == "Customer 10"
    refute Enum.any?(customers, &(&1.buyer == "Earlier Shopper"))
  end

  test "only an admin can look customers up", %{admin: admin} do
    invoice(admin, %{})
    assert {:error, %Ash.Error.Forbidden{}} = Payments.find_invoice_customers("anna", actor: nil)
  end
end
