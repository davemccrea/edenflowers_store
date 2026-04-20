defmodule EdenflowersWeb.InvoiceComponent do
  @moduledoc """
  Finnish invoice (lasku) component.

  Renders a print-ready A4 invoice that follows Finnish invoicing conventions:
  - DD.MM.YYYY date format
  - Comma decimal separator (e.g. 1 234,56 €)
  - Finnish reference number (viitenumero) grouped in 5-digit blocks
  - IBAN formatted in 4-character groups
  - VAT (ALV) broken down by rate in the totals section
  - Payment slip footer styled as a detachable tilisiirto section
  """
  use EdenflowersWeb, :html

  # ---------------------------------------------------------------------------
  # Seller / buyer info structs
  # ---------------------------------------------------------------------------

  @type party :: %{
          name: String.t(),
          address_line1: String.t(),
          address_line2: String.t(),
          # e.g. "1234567-8"
          business_id: String.t() | nil,
          # e.g. "FI12345678"
          vat_number: String.t() | nil,
          email: String.t() | nil,
          phone: String.t() | nil,
          website: String.t() | nil
        }

  @type bank_details :: %{
          # e.g. "FI21 1234 5600 0007 85"
          iban: String.t(),
          # e.g. "NDEAFIHH"
          bic: String.t() | nil
        }

  @type vat_line :: %{
          # e.g. 25.5
          rate: float(),
          # taxable base in cents
          base_amount: integer(),
          # vat amount in cents
          vat_amount: integer()
        }

  @type line_item :: %{
          description: String.t(),
          quantity: Decimal.t() | float() | integer(),
          unit: String.t(),
          unit_price: integer(),
          vat_rate: float()
        }

  # ---------------------------------------------------------------------------
  # Component
  # ---------------------------------------------------------------------------

  attr :invoice_number, :string, required: true
  attr :invoice_date, Date, required: true
  attr :due_date, Date, required: true
  # e.g. "14 pv netto"
  attr :payment_terms, :string, default: "14 pv netto"
  # e.g. 7.0
  attr :late_payment_interest, :float, default: 7.0
  attr :seller, :map, required: true
  attr :buyer, :map, required: true
  attr :line_items, :list, required: true
  attr :vat_lines, :list, required: true
  # total amount due in cents
  attr :total_amount, :integer, required: true
  attr :bank_details, :map, required: true
  # Finnish reference number, already formatted e.g. "12345 67890 3"
  attr :reference_number, :string, required: true
  # optional free-text note at bottom of line items
  attr :notes, :string, default: nil

  def invoice(assigns) do
    ~H"""
    <article class="font-sans text-sm text-gray-900 bg-white mx-auto w-full max-w-[210mm] min-h-[297mm] p-[15mm] print:p-0 print:max-w-none print:shadow-none shadow-lg">

      <%!-- ── 1. Header: seller + title ─────────────────────────────── --%>
      <header class="invoice-section flex items-start justify-between border-b border-gray-300 pb-6 mb-6">
        <div class="space-y-0.5">
          <p class="text-base font-bold">{@seller.name}</p>
          <p class="text-gray-600">{@seller.address_line1}</p>
          <p class="text-gray-600">{@seller.address_line2}</p>
          <p :if={@seller[:email]} class="text-gray-600">{@seller.email}</p>
          <p :if={@seller[:phone]} class="text-gray-600">{@seller.phone}</p>
          <p :if={@seller[:website]} class="text-gray-600">{@seller.website}</p>
          <p :if={@seller[:business_id]} class="text-gray-600 pt-1">
            Y-tunnus: {@seller.business_id}
          </p>
          <p :if={@seller[:vat_number]} class="text-gray-600">
            ALV-nro: {@seller.vat_number} alv. rek.
          </p>
        </div>
        <div class="text-right">
          <h1 class="text-3xl font-bold tracking-widest uppercase text-gray-800">Lasku</h1>
        </div>
      </header>

      <%!-- ── 2. Meta: buyer (left) + invoice details (right) ───────── --%>
      <section class="invoice-section flex gap-8 mb-8">
        <div class="flex-1 space-y-0.5">
          <p class="text-xs font-semibold uppercase tracking-wider text-gray-500 mb-1">Laskun saaja</p>
          <p class="font-semibold">{@buyer.name}</p>
          <p class="text-gray-600">{@buyer.address_line1}</p>
          <p class="text-gray-600">{@buyer.address_line2}</p>
          <p :if={@buyer[:business_id]} class="text-gray-600 pt-1">
            Y-tunnus: {@buyer.business_id}
          </p>
          <p :if={@buyer[:vat_number]} class="text-gray-600">
            ALV-nro: {@buyer.vat_number}
          </p>
        </div>

        <dl class="grid grid-cols-[auto_1fr] gap-x-6 gap-y-1 text-right self-start">
          <dt class="text-gray-500 text-right">Laskun numero</dt>
          <dd class="font-semibold">{@invoice_number}</dd>

          <dt class="text-gray-500 text-right">Laskun päivämäärä</dt>
          <dd>{format_date(@invoice_date)}</dd>

          <dt class="text-gray-500 text-right">Eräpäivä</dt>
          <dd class="font-semibold">{format_date(@due_date)}</dd>

          <dt class="text-gray-500 text-right">Maksuehto</dt>
          <dd>{@payment_terms}</dd>

          <dt class="text-gray-500 text-right">Viivästyskorko</dt>
          <dd>{format_percent(@late_payment_interest)} %</dd>
        </dl>
      </section>

      <%!-- ── 3. Line items ──────────────────────────────────────────── --%>
      <section class="invoice-section mb-6">
        <table class="w-full text-sm border-collapse">
          <thead>
            <tr class="border-b-2 border-gray-900">
              <th class="py-2 text-left font-semibold">Kuvaus</th>
              <th class="py-2 text-right font-semibold">Määrä</th>
              <th class="py-2 text-right font-semibold px-2">Yksikkö</th>
              <th class="py-2 text-right font-semibold">Á-hinta</th>
              <th class="py-2 text-right font-semibold px-2">ALV %</th>
              <th class="py-2 text-right font-semibold">Yhteensä</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={item <- @line_items} class="border-b border-gray-200">
              <td class="py-2 pr-4">{item.description}</td>
              <td class="py-2 text-right">{format_quantity(item.quantity)}</td>
              <td class="py-2 text-right px-2 text-gray-600">{item.unit}</td>
              <td class="py-2 text-right">{format_amount(item.unit_price)}</td>
              <td class="py-2 text-right px-2 text-gray-600">{format_percent(item.vat_rate)} %</td>
              <td class="py-2 text-right">{format_amount(line_total(item))}</td>
            </tr>
          </tbody>
        </table>

        <p :if={@notes} class="mt-4 text-xs text-gray-500 italic">{@notes}</p>
      </section>

      <%!-- ── 4. Totals ───────────────────────────────────────────────── --%>
      <section class="invoice-section flex justify-end mb-8">
        <dl class="grid grid-cols-[auto_1fr] gap-x-8 gap-y-1 min-w-[16rem]">
          <dt :for={vl <- @vat_lines} class="text-gray-500">
            Veroton hinta ({format_percent(vl.rate)} %)
          </dt>
          <dd :for={vl <- @vat_lines} class="text-right">{format_amount(vl.base_amount)} €</dd>

          <dt :for={vl <- @vat_lines} class="text-gray-500">
            ALV {format_percent(vl.rate)} %
          </dt>
          <dd :for={vl <- @vat_lines} class="text-right">{format_amount(vl.vat_amount)} €</dd>

          <dt class="border-t border-gray-300 pt-2 mt-1 font-semibold">Yhteensä</dt>
          <dd class="border-t border-gray-300 pt-2 mt-1 text-right font-semibold">
            {format_amount(@total_amount)} €
          </dd>

          <dt class="text-base font-bold pt-1">Maksettava</dt>
          <dd class="text-base font-bold text-right pt-1">{format_amount(@total_amount)} €</dd>
        </dl>
      </section>

      <%!-- ── 5. Payment slip (tilisiirto) ───────────────────────────── --%>
      <footer class="invoice-payment-slip border-t-2 border-dashed border-gray-400 pt-6 mt-auto">
        <p class="text-xs font-semibold uppercase tracking-wider text-gray-500 mb-3">Maksutiedot</p>
        <dl class="grid grid-cols-[auto_1fr] gap-x-8 gap-y-1">
          <dt class="text-gray-500">Saaja</dt>
          <dd class="font-semibold">{@seller.name}</dd>

          <dt class="text-gray-500">IBAN</dt>
          <dd class="font-mono">{@bank_details.iban}</dd>

          <dt :if={@bank_details[:bic]} class="text-gray-500">BIC</dt>
          <dd :if={@bank_details[:bic]} class="font-mono">{@bank_details.bic}</dd>

          <dt class="text-gray-500">Viitenumero</dt>
          <dd class="font-mono font-semibold">{@reference_number}</dd>

          <dt class="text-gray-500">Eräpäivä</dt>
          <dd class="font-semibold">{format_date(@due_date)}</dd>

          <dt class="text-gray-500">Maksettava</dt>
          <dd class="text-base font-bold">{format_amount(@total_amount)} €</dd>
        </dl>
      </footer>
    </article>
    """
  end

  # ---------------------------------------------------------------------------
  # Formatting helpers
  # ---------------------------------------------------------------------------

  defp format_date(%Date{} = date) do
    day = date.day |> Integer.to_string() |> String.pad_leading(2, "0")
    month = date.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{day}.#{month}.#{date.year}"
  end

  # Formats cents as Finnish decimal string e.g. 123456 -> "1 234,56"
  defp format_amount(cents) when is_integer(cents) do
    euros = div(cents, 100)
    cents_part = rem(cents, 100) |> abs() |> Integer.to_string() |> String.pad_leading(2, "0")
    euros_str = euros |> Integer.to_string() |> add_thousands_sep()
    "#{euros_str},#{cents_part}"
  end

  # Inserts non-breaking spaces as thousands separators (Finnish convention)
  defp add_thousands_sep(str) do
    str
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.join("\u00A0")
    |> String.reverse()
  end

  defp format_percent(rate) when is_float(rate) do
    if rate == Float.floor(rate) do
      rate |> trunc() |> Integer.to_string()
    else
      :erlang.float_to_binary(rate, decimals: 1) |> String.replace(".", ",")
    end
  end

  defp format_quantity(qty) when is_integer(qty), do: Integer.to_string(qty)
  defp format_quantity(qty) when is_float(qty), do: format_percent(qty)

  defp format_quantity(%Decimal{} = qty) do
    qty |> Decimal.to_string(:normal) |> String.replace(".", ",")
  end

  # Line total in cents (unit_price is in cents)
  defp line_total(%{quantity: qty, unit_price: unit_price, vat_rate: rate})
       when is_integer(qty) do
    net = qty * unit_price
    vat = round(net * rate / 100)
    net + vat
  end

  defp line_total(%{quantity: qty, unit_price: unit_price, vat_rate: rate})
       when is_float(qty) do
    net = round(qty * unit_price)
    vat = round(net * rate / 100)
    net + vat
  end
end
