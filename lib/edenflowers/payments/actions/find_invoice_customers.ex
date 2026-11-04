defmodule Edenflowers.Payments.Actions.FindInvoiceCustomers do
  @moduledoc """
  The customers an invoice draft can be filled from: each invoice customer's
  latest issued invoice, and shop customers with a placed order whose email
  has no invoice yet. Most recently billed or ordered first.
  """

  use Ash.Resource.Actions.Implementation

  alias Edenflowers.Accounts
  alias Edenflowers.Payments

  @limit 10

  @impl true
  def run(input, _opts, context) do
    term = input.arguments[:term]
    opts = Ash.Context.to_opts(context)

    with {:ok, invoices} <- Payments.search_invoice_customers(term, Keyword.put(opts, :query, limit: @limit)),
         {:ok, users} <-
           Accounts.search_customers(term, opts ++ [query: [limit: @limit], load: [:last_ordered_at, :order_locale]]) do
      invoiced = MapSet.new(invoices, &email_key(&1.buyer_email))

      customers =
        Enum.map(invoices, &from_invoice/1) ++
          for user <- users, not MapSet.member?(invoiced, email_key(user.email)), do: from_user(user)

      {:ok, customers |> Enum.sort_by(& &1.last_seen_at, {:desc, DateTime}) |> Enum.take(@limit)}
    end
  end

  defp email_key(email), do: email |> to_string() |> String.downcase()

  defp from_invoice(invoice) do
    %{
      id: invoice.id,
      buyer: invoice.buyer,
      buyer_email: to_string(invoice.buyer_email),
      last_seen_at: invoice.issued_at,
      details: %{
        buyer_name: invoice.buyer_name,
        buyer_email: invoice.buyer_email,
        business_customer: invoice.business_customer,
        company_name: invoice.company_name,
        business_id: invoice.business_id,
        billing_address: invoice.billing_address,
        locale: invoice.locale
      }
    }
  end

  defp from_user(user) do
    %{
      id: user.id,
      buyer: user.name,
      buyer_email: to_string(user.email),
      last_seen_at: user.last_ordered_at,
      details: %{
        buyer_name: user.name,
        buyer_email: to_string(user.email),
        business_customer: false,
        company_name: nil,
        business_id: nil,
        billing_address: nil,
        locale: user.order_locale
      }
    }
  end
end
