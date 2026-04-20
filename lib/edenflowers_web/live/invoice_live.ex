defmodule EdenflowersWeb.InvoiceLive do
  use EdenflowersWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: {EdenflowersWeb.Layouts, :invoice}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <EdenflowersWeb.InvoiceComponent.invoice
      invoice_number="2026-0001"
      invoice_date={~D[2026-04-21]}
      due_date={~D[2026-05-05]}
      payment_terms="14 pv netto"
      late_payment_interest={7.0}
      seller={%{
        name: "Eden Flowers Oy",
        address_line1: "Puutarhakatu 12",
        address_line2: "00100 Helsinki",
        business_id: "1234567-8",
        vat_number: "FI12345678",
        email: "info@edenflowers.fi",
        phone: "+358 9 123 4567",
        website: "www.edenflowers.fi"
      }}
      buyer={%{
        name: "Esimerkki Yritys Oy",
        address_line1: "Liiketie 4 B",
        address_line2: "00200 Helsinki",
        business_id: "8765432-1",
        vat_number: "FI87654321"
      }}
      line_items={[
        %{description: "Hääkukkakimppu, valkoinen", quantity: 2, unit: "kpl", unit_price: 8500, vat_rate: 25.5},
        %{description: "Pöytäkoriste, kevätkukat", quantity: 10, unit: "kpl", unit_price: 3200, vat_rate: 25.5},
        %{description: "Kukka-asetelma, suurikokoinen", quantity: 1, unit: "kpl", unit_price: 15000, vat_rate: 25.5},
        %{description: "Toimituskulut", quantity: 1, unit: "kpl", unit_price: 1500, vat_rate: 25.5}
      ]}
      vat_lines={[
        %{rate: 25.5, base_amount: 65500, vat_amount: 16703}
      ]}
      total_amount={82203}
      bank_details={%{iban: "FI21 1234 5600 0007 85", bic: "NDEAFIHH"}}
      reference_number="12345 67890 3"
      notes="Kiitos tilauksestanne! — Thank you for your order!"
    />
    """
  end
end
