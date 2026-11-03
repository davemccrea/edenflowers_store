defmodule Edenflowers.Payments.InvoiceLine do
  @moduledoc """
  One billed line of an Invoice. A draft may hold a line Jennie hasn't
  finished, so every field may be blank, but what she has entered must make
  sense. Issuing needs every field (`Changes.IssueInvoice.field_errors/1`),
  then `InvoiceFinancials` totals the lines into the frozen snapshot.
  """
  use Ash.Resource, data_layer: :embedded

  alias Edenflowers.Types.DecimalComma

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    attribute :description, :string do
      description "What was supplied, as printed on the invoice."
      public? true
    end

    attribute :quantity, DecimalComma do
      description "How many, which may be fractional, such as 1,5 hours."
      public? true
      constraints greater_than: 0
    end

    attribute :unit_price, DecimalComma do
      description "The price of one in euros, VAT included, kept to the precision typed: 0,005 stays 0,005."
      public? true
      constraints min: 0
    end

    attribute :vat_rate, DecimalComma do
      description "The VAT rate in percent, such as 25,5."
      public? true
      constraints min: 0, max: 100
    end
  end
end
