defmodule EdenflowersWeb.Admin.InvoiceLogTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.Admin.InvoiceLog

  test "combines financial records and email versions in newest-first order" do
    invoice = %{
      inserted_at: ~U[2026-11-01 08:00:00Z],
      issued_at: ~U[2026-11-01 09:00:00Z],
      sent_at: ~U[2026-11-02 10:00:00Z],
      buyer_email: "customer@example.com",
      paper_trail_versions: [
        %{version_inserted_at: ~U[2026-11-01 10:00:00Z], reminder: false, email_message: "Original message"},
        %{version_inserted_at: ~U[2026-11-02 10:00:00Z], reminder: true, email_message: "Reminder message"}
      ],
      payments: [
        %{
          paid_at: ~U[2026-11-02 11:00:00Z],
          amount: Decimal.new("10"),
          method: :zervant,
          reverses_payment_id: nil,
          note: nil
        },
        %{
          paid_at: ~U[2026-11-02 12:00:00Z],
          amount: Decimal.new("-10"),
          method: :zervant,
          reverses_payment_id: "original-payment",
          note: nil
        }
      ],
      credit_note: %{
        inserted_at: ~U[2026-11-02 13:00:00Z],
        number: 1338,
        reason: "Incorrect address",
        paper_trail_versions: [
          %{version_inserted_at: ~U[2026-11-02 14:00:00Z], email_message: "Credit message"}
        ]
      }
    }

    entries = InvoiceLog.entries(invoice, "en-GB")

    assert Enum.map(entries, & &1.at) == [
             ~U[2026-11-02 14:00:00Z],
             ~U[2026-11-02 13:00:00Z],
             ~U[2026-11-02 12:00:00Z],
             ~U[2026-11-02 11:00:00Z],
             ~U[2026-11-02 10:00:00Z],
             ~U[2026-11-01 10:00:00Z],
             ~U[2026-11-01 09:00:00Z],
             ~U[2026-11-01 08:00:00Z]
           ]

    assert Enum.map(entries, & &1.title) |> Enum.any?(&String.starts_with?(&1, "Undid"))
    assert Enum.at(entries, 4).title == "Payment reminder emailed"
    assert Enum.at(entries, 5).title == "Invoice emailed"
    assert {"Message", "Credit message"} in hd(entries).details
    assert {"Reason", "Incorrect address"} in Enum.at(entries, 1).details
    assert {"Sent to", "customer@example.com"} in Enum.at(entries, 5).details
  end
end
