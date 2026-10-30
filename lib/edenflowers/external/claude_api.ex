defmodule Edenflowers.External.ClaudeAPI.Behaviour do
  @moduledoc """
  Contract for the Claude calls used by receipt extraction and translation.
  """

  @callback extract_expense(file_binary :: binary(), content_type :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback translate(fields :: %{String.t() => String.t() | nil}, from :: String.t()) ::
              {:ok, %{String.t() => %{String.t() => String.t()}}} | {:error, term()}
end

defmodule Edenflowers.External.ClaudeAPI do
  @moduledoc """
  Calls Claude through `ReqLLM` for expense extraction and for translating
  shop copy between the store languages.

  For expenses, the prompt and output schema live here. The returned map is handed straight
  to `Edenflowers.Expenses.Expense` for ingestion, which performs all type
  coercion (string → Date, decimal string → Decimal, string → enum). This module does
  no casting of its own.
  """

  @behaviour Edenflowers.External.ClaudeAPI.Behaviour

  alias Edenflowers.Expenses.Expense.Category
  alias ReqLLM.Context
  alias ReqLLM.Message.ContentPart

  @model "anthropic:claude-sonnet-4-6"

  @schema [
    vendor_name: [type: :string, doc: "Name of the vendor or supplier."],
    vendor_vat_number: [type: :string, doc: "The vendor's VAT/tax number, if present."],
    date: [type: :string, doc: "Invoice/receipt date in ISO 8601 format (YYYY-MM-DD)."],
    paid_on: [
      type: :string,
      doc:
        "Only if the document shows it has already been paid (a till or card receipt, an order confirmation charged to a card, an invoice marked paid): the payment date in ISO 8601 format. Omit for an invoice still to be paid."
    ],
    due_on: [type: :string, doc: "For an invoice still to be paid, its due date in ISO 8601 format, if shown."],
    total_amount: [type: :string, doc: "Total amount including VAT as a decimal string, e.g. 121.00."],
    vat_amount: [type: :string, doc: "VAT/tax amount as a decimal string, e.g. 25.50, if shown separately."],
    currency: [type: :string, doc: "ISO 4217 currency code, lowercase (e.g. eur, sek)."],
    category: [
      type: {:in, Enum.map(Category.values(), &Atom.to_string/1)},
      doc:
        "The category that best fits what was purchased:\n" <>
          Enum.map_join(Category.values(), "\n", &"- #{&1}: #{Category.description(&1)}")
    ],
    description: [type: :string, doc: "Short description of what was purchased, in Finland Swedish."],
    confidence: [
      type: :string,
      required: true,
      doc: "Overall extraction certainty across all fields: high, medium, or low."
    ]
  ]

  @prompt """
  Extract the expense details from this receipt or invoice.
  Use a lowercase ISO 4217 code for the currency.
  Write the description in Finland Swedish, whatever the language of the document.
  Decide whether the document shows it has already been paid, or is an invoice still to be paid.
  Omit any field you cannot determine with reasonable confidence.
  Set confidence to reflect your overall certainty across all fields.
  """

  @translation_model "anthropic:claude-opus-5-5"

  @languages %{"en-GB" => "British English", "sv-FI" => "Finland Swedish", "fi" => "Finnish"}

  @doc "The configured implementation: this module, or the mock in tests."
  def impl, do: Application.get_env(:edenflowers, :claude_api, __MODULE__)

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

  @doc """
  Translate a name and description from one store locale into the others.

  Takes `%{"name" => .., "description" => ..}` and returns
  `%{locale => %{"name" => .., "description" => ..}}` for every other locale.
  """
  @impl true
  def translate(fields, from) do
    targets = Edenflowers.Locales.all() -- [from]

    schema =
      for locale <- targets, field <- ["name", "description"] do
        # A fixed set of locale and field keys, so no unbounded atom creation.
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        {String.to_atom(key(locale, field)),
         [type: :string, required: true, doc: "The #{field} in #{@languages[locale]}."]}
      end

    prompt = """
    You translate copy for Eden Flowers, a florist in Finland, from #{@languages[from]} into #{Enum.map_join(targets, " and ", &@languages[&1])}.
    The copy is the name and description of a product or a flower-arranging course shown in the online shop.
    Write naturally for local customers and keep the tone, meaning and line breaks.
    Leave place names, street addresses and brand names untranslated.
    If the description is empty, return empty descriptions.

    Name: #{fields["name"]}

    Description:
    #{fields["description"]}
    """

    case ReqLLM.generate_object(@translation_model, prompt, schema, api_key: api_key()) do
      {:ok, response} ->
        object = ReqLLM.Response.object(response)

        {:ok,
         Map.new(targets, fn locale ->
           {locale, %{"name" => object[key(locale, "name")], "description" => object[key(locale, "description")]}}
         end)}

      {:error, reason} ->
        {:error, {:claude_translation_failed, reason}}
    end
  end

  defp key(locale, field), do: String.replace(String.downcase(locale), "-", "_") <> "_" <> field

  defp api_key, do: Application.get_env(:edenflowers, :anthropic_api_key)
end
