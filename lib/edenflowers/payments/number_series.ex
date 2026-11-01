defmodule Edenflowers.Payments.NumberSeries do
  @moduledoc """
  The one gapless number series Invoices and Credit notes share, continuing
  Zervant's from `Invoice.first_number/0`.

  A number is taken inside the insert's transaction, under a lock every
  invoice and credit note takes, as the highest number in either table + 1.
  A Postgres sequence would leave a gap whenever an insert rolled back; this
  way a failed insert frees its number for the next one.
  """

  alias Edenflowers.Payments.Invoice
  alias Edenflowers.Repo

  # ponytail: one lock for every invoice and credit note; fine for one shop's handful a month.
  @doc "The next number in the series. Call it only inside the transaction that inserts it."
  def take do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext('invoice_number'))")

    %{rows: [[last]]} =
      Repo.query!("SELECT GREATEST((SELECT max(number) FROM invoices), (SELECT max(number) FROM credit_notes))")

    if last, do: last + 1, else: Invoice.first_number()
  end
end
