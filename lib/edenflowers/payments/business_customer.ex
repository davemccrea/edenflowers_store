defmodule Edenflowers.Payments.BusinessCustomer do
  @moduledoc """
  Who an invoice for an order or a course booking is addressed to when the
  buyer is a company. Jennie fills the details in whenever she learns them,
  so saving never needs them; only invoicing does, through
  `business_details_complete?`.
  """
  use Spark.Dsl.Fragment, of: Ash.Resource

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
  end
end
