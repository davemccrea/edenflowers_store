defmodule Edenflowers.Payments.Validations.Invoiceable do
  @moduledoc """
  Refuses an invoice for a purchase that isn't `invoiceable?`, read fresh,
  saying what is missing. The same calculation tells the admin whether to
  offer invoicing at all.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  alias Edenflowers.Payments.Invoice

  @impl true
  def validate(changeset, _opts, _context) do
    load = [:invoiceable?, :committed?, :payment_terms, :business_details_complete?]

    case Invoice.purchase(changeset, load) do
      nil -> :ok
      %{invoiceable?: true} -> :ok
      %{committed?: false} -> error(~t"Only a placed order or a confirmed booking can be invoiced.")
      %{payment_terms: terms} when terms != :invoice -> error(~t"Only a purchase on invoice terms can be invoiced.")
      %{business_details_complete?: false} -> error(~t"Fill in the company name, Y-tunnus and billing address first.")
      _ -> error(~t"Fill in the customer's name and email first.")
    end
  end

  defp error(message), do: {:error, message: message}
end
