defmodule Edenflowers.Payments.InvoicePaymentConcurrencyTest do
  use Edenflowers.DataCase, async: false
  alias Ecto.Adapters.SQL.Sandbox
  alias Edenflowers.Payments

  test "independent payment and credit transactions cannot both succeed" do
    actor = %{admin: true}

    invoice =
      Sandbox.unboxed_run(Edenflowers.Repo, fn ->
        {:ok, draft} =
          Payments.create_invoice(
            %{
              buyer_name: "Concurrent buyer",
              buyer_email: "buyer@example.com",
              buyer_address: "Street 1",
              lines: [%{description: "Flowers", quantity: "1", unit_price: "100", vat_rate: "25.5"}]
            },
            actor: actor
          )

        {:ok, invoice} = Payments.issue_invoice(draft, actor: actor)
        invoice
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Edenflowers.Repo, fn ->
        Edenflowers.Repo.query!("DELETE FROM payments WHERE invoice_id::text = $1", [invoice.id])
        Edenflowers.Repo.query!("DELETE FROM credit_notes WHERE invoice_id::text = $1", [invoice.id])
        Edenflowers.Repo.query!("DELETE FROM invoices WHERE id::text = $1", [invoice.id])
      end)
    end)

    actions = [
      fn -> Payments.record_invoice_payment(invoice, "1", actor: actor) end,
      fn -> Payments.cancel_invoice(%{invoice_id: invoice.id}, actor: actor) end
    ]

    results =
      Enum.map(actions, fn action ->
        Task.async(fn -> Sandbox.unboxed_run(Edenflowers.Repo, action) end)
      end)
      |> Task.await_many(15_000)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
  end
end
