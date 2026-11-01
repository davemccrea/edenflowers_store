defmodule Edenflowers.Payments.Changes.SendInvoice do
  @moduledoc """
  Emails an invoice to its buyer in the invoice's own language, with its PDF
  and Jennie's message, then stamps `sent_at`. The PDF is made first, so a
  render failure sends nothing.
  """
  use Ash.Resource.Change

  require Logger

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Payments.InvoicePdf
  alias Edenflowers.Translations

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      invoice = changeset.data
      message = Ash.Changeset.get_argument(changeset, :message)

      with {:ok, pdf} <- InvoicePdf.generate(invoice),
           {:ok, _result} <-
             invoice
             |> load_for_email()
             |> Email.invoice(message)
             |> Swoosh.Email.attachment(InvoicePdf.attachment(pdf, invoice))
             |> Mailer.deliver() do
        Logger.info("Sent invoice #{invoice.number} (#{invoice.id})")
        Ash.Changeset.force_change_attribute(changeset, :sent_at, DateTime.utc_now())
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, "Failed to send invoice: #{inspect(error)}")
      end
    end)
  end

  @doc """
  Loads what `Email.invoice/2` reads: the order or the booking with its
  course, in the invoice's language, and the purchase's Total due.
  """
  def load_for_email(invoice) do
    invoice
    |> Ash.load!([order: [:total_due, :balance], course_registration: [:course, :total_due, :balance]],
      authorize?: false
    )
    |> in_invoice_locale()
  end

  @doc "Puts a loaded booking's course into the invoice's language, which Jennie may have changed from the booking's."
  def in_invoice_locale(%{course_registration: %CourseRegistration{} = registration} = invoice),
    do: %{invoice | course_registration: Translations.in_own_locale(%{registration | locale: invoice.locale})}

  def in_invoice_locale(invoice), do: invoice
end
