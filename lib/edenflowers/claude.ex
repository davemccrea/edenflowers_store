defmodule Edenflowers.Claude.Behaviour do
  @callback extract_expense(file_binary :: binary(), content_type :: String.t()) ::
              {:ok, map()} | {:error, term()}
end

defmodule Edenflowers.Claude do
  @moduledoc """
  Extracts structured expense data from a receipt or invoice document using
  `ReqLLM`.

  The prompt and output schema live here. The returned map is handed straight
  to `Edenflowers.Expenses.Expense` for ingestion, which performs all type
  coercion (string → Date, float → Decimal, string → enum). This module does
  no casting of its own.
  """

  @behaviour Edenflowers.Claude.Behaviour

  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart

  @model "anthropic:claude-sonnet-4-6"

  @schema [
    vendor_name: [type: :string, doc: "Name of the vendor or supplier."],
    vendor_vat_number: [type: :string, doc: "The vendor's VAT/tax number, if present."],
    date: [type: :string, doc: "Invoice/receipt date in ISO 8601 format (YYYY-MM-DD)."],
    total_amount: [type: :float, doc: "Total amount including VAT."],
    vat_amount: [type: :float, doc: "VAT/tax amount, if shown separately."],
    currency: [type: :string, doc: "ISO 4217 currency code, lowercase (e.g. eur, sek)."],
    category: [
      type: :string,
      doc:
        "One of: office_supplies, travel, meals, software, marketing, utilities, professional_services, other."
    ],
    description: [type: :string, doc: "Short description of what was purchased."],
    confidence: [
      type: :string,
      required: true,
      doc: "Overall extraction certainty across all fields: high, medium, or low."
    ]
  ]

  @prompt """
  Extract the expense details from this receipt or invoice.
  Use a lowercase ISO 4217 code for the currency and a lowercase value for the category.
  Omit any field you cannot determine with reasonable confidence.
  Set confidence to reflect your overall certainty across all fields.
  """

  @impl true
  def extract_expense(file_binary, content_type) do
    context =
      Context.new([
        Context.user([
          ContentPart.text(@prompt),
          ContentPart.file(file_binary, "document", content_type)
        ])
      ])

    case ReqLLM.generate_object(@model, context, @schema, api_key: api_key()) do
      {:ok, response} -> {:ok, ReqLLM.Response.object(response)}
      {:error, reason} -> {:error, {:claude_extraction_failed, reason}}
    end
  end

  defp api_key, do: Application.get_env(:edenflowers, :anthropic_api_key)
end
