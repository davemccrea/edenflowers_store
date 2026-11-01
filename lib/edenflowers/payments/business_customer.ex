defmodule Edenflowers.Payments.BusinessCustomer do
  @moduledoc """
  Who an invoice for an order or a course booking is addressed to when the
  buyer is a company. Jennie fills the details in whenever she learns them,
  so saving never needs them; only invoicing does, through
  `business_details_complete?`.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

  alias Edenflowers.Orders.Validations.Holds

  actions do
    update :update_business_details do
      description "Jennie fills in or corrects who an invoice is addressed to, whatever the order or booking's " <>
                    "fulfilment: invoices usually go out after delivery, and a cancelled purchase may still be " <>
                    "invoiced for what she kept. Changes nothing else. Invoices already made keep the details " <>
                    "they were sent with."

      accept [:business_customer, :company_name, :business_id, :billing_address, :customer_reference]
      validate {Holds, calculation: :committed?, message: "is not placed or confirmed"}
    end
  end

  attributes do
    attribute :business_customer, :boolean do
      description "Whether a company is buying, so its invoice is addressed to the company with its Y-tunnus."
      allow_nil? false
      default false
    end

    attribute :company_name, :string do
      description "The buying company's name, as printed on its invoice."
    end

    attribute :business_id, Edenflowers.Types.BusinessId do
      description "The buying company's Y-tunnus, such as 1234567-8, checked for its format and check digit."
    end

    attribute :billing_address, :string do
      description "Where the company is billed, one line per row, as printed on its invoice."
    end

    attribute :customer_reference, :string do
      description "The company's own reference for the purchase (viitteenne), such as a PO number, printed on " <>
                    "its invoice. Optional."
    end
  end

  calculations do
    calculate :business_details_complete?,
              :boolean,
              expr(
                not business_customer or
                  (not is_nil(company_name) and not is_nil(business_id) and not is_nil(billing_address))
              ) do
      description "Whether an invoice can be addressed: always for a consumer, and for a business customer once " <>
                    "company name, Y-tunnus and billing address are all filled in. Saving never needs this; " <>
                    "creating an invoice does."
    end

    calculate :missing_business_details,
              {:array, :atom},
              fn records, _context ->
                Enum.map(records, fn
                  %{business_customer: true} = record ->
                    Enum.filter([:company_name, :business_id, :billing_address], &is_nil(Map.get(record, &1)))

                  _consumer ->
                    []
                end)
              end do
      description "Which of company_name, business_id and billing_address a business customer still lacks before " <>
                    "it can be invoiced, so the admin can name them. Empty for a consumer and once complete."
    end
  end
end
