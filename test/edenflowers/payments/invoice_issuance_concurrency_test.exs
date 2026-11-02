defmodule Edenflowers.Payments.InvoiceIssuanceConcurrencyTest do
  use Edenflowers.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Edenflowers.Payments

  test "independent transactions cannot issue the same draft twice or duplicate document numbers" do
    attrs = %{
      buyer_name: "Concurrency buyer",
      buyer_email: "buyer@example.com",
      buyer_address: "Street 1",
      lines: [%{"description" => "Flowers", "quantity" => "1", "unit_price" => "10", "vat_rate" => "25.5"}]
    }

    actor = %{admin: true}

    drafts =
      Sandbox.unboxed_run(Edenflowers.Repo, fn ->
        for _ <- 1..2 do
          {:ok, draft} = Payments.create_invoice(attrs, actor: actor)
          draft
        end
      end)

    ids = Enum.map(drafts, & &1.id)

    on_exit(fn ->
      Sandbox.unboxed_run(Edenflowers.Repo, fn ->
        Edenflowers.Repo.query!("DELETE FROM invoices WHERE id::text = ANY($1::text[])", [ids])
      end)
    end)

    [first, second] = drafts

    results =
      [first, first, second]
      |> Enum.map(fn draft ->
        Task.async(fn ->
          Sandbox.unboxed_run(Edenflowers.Repo, fn -> Payments.issue_invoice(draft, actor: actor) end)
        end)
      end)
      |> Task.await_many(15_000)

    issued = for {:ok, invoice} <- results, do: invoice
    assert length(issued) == 2
    assert Enum.count(results, &match?({:error, _}, &1)) == 1
    assert issued |> Enum.map(& &1.number) |> Enum.uniq() |> length() == 2
  end
end
