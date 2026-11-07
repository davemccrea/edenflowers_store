defmodule EdenflowersWeb.Admin.EmailDrawer do
  @moduledoc """
  The state behind `EdenflowersWeb.Admin.Drawers.email_drawer`, shared by
  the order, course and invoice pages: an AshPhoenix form on the action that
  sends each kind, the preview built when it opens, and what each kind is
  called. A failed send keeps the drawer open with her edits, and an address
  the action refuses marked on its field. The pages flash what happened, in
  their words for each kind: a failed send's own error is for the log.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext, sigils: [domain: "admin"]

  require Logger

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 1]
  import Phoenix.LiveView, only: [clear_flash: 2, push_event: 3]

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias Edenflowers.Payments.CreditNote
  alias Edenflowers.Payments.Invoice
  alias EdenflowersWeb.Admin.DrawerPreview
  alias EdenflowersWeb.Admin.Drawers

  @doc """
  Opens the drawer for `kind`, previewing the email as it would go now.
  `assigns` is for what else the page tracks about it, like which booking.
  """
  def open(socket, kind, record, assigns \\ []) do
    kind = String.to_existing_atom(kind)

    form =
      record
      |> AshPhoenix.Form.for_update(action(kind, record),
        as: "email",
        actor: socket.assigns.current_user,
        transform_params: &Drawers.keep_email_edits/3
      )
      |> to_form()

    socket
    |> assign(assigns)
    |> assign(email_kind: kind, email_form: form)
    |> assign(:preview, DrawerPreview.build(kind, record, form))
    |> push_event("js-exec", %{to: "#email-drawer", attr: "phx-show"})
  end

  @doc "Closes the drawer, forgetting its form and preview."
  def close(socket, assigns \\ []) do
    socket
    |> assign(assigns)
    |> assign(email_form: nil, email_kind: nil, preview: nil)
    |> push_event("js-exec", %{to: "#email-drawer", attr: "phx-hide"})
  end

  @doc "Validates the email edits, keeping the template preview from when the drawer opened."
  def validate(socket, params),
    do: assign(socket, :email_form, AshPhoenix.Form.validate(socket.assigns.email_form, params))

  @doc """
  Sends the email: `{:ok, socket}` once it went, for the page to close the
  drawer and say so, or `{:error, socket}` with the drawer still open as
  Jennie filled it in.
  """
  def submit(socket, params) do
    case AshPhoenix.Form.submit(socket.assigns.email_form, params: params) do
      # An earlier try's failure no longer stands.
      {:ok, _record} ->
        {:ok, clear_flash(socket, :error)}

      {:error, form} ->
        Logger.warning("#{socket.assigns.email_kind} email not sent: #{inspect(AshPhoenix.Form.raw_errors(form))}")
        {:error, assign(socket, email_form: form)}
    end
  end

  defp action(:order_details, %Order{}), do: :send_order_details_email
  defp action(:gift_voucher, %Order{}), do: :email_gift_voucher
  defp action(:receipt, %Order{}), do: :email_receipt
  defp action(:fulfillment, %Order{}), do: :email_fulfillment_confirmation
  defp action(:payment_reminder, %Order{}), do: :send_payment_reminder
  defp action(:payment_reminder, %CourseRegistration{}), do: :send_payment_reminder
  defp action(:payment_link, %CourseRegistration{}), do: :email_payment_link
  defp action(:confirmation, %CourseRegistration{}), do: :email_receipt
  defp action(:invoice, %Invoice{}), do: :send
  defp action(:credit_note, %CreditNote{}), do: :send

  @doc "The drawer's heading, button and recipient for `kind`."
  def text(nil, _record, _locale), do: %{}
  def text(_kind, nil, _locale), do: %{}

  def text(:invoice, %Invoice{} = invoice, locale) do
    %{
      title: ~t"Email invoice",
      submit_label: invoice_send_label(invoice),
      to: invoice.buyer_email,
      last_sent: invoice.sent_at && Format.datetime(invoice.sent_at, locale)
    }
  end

  def text(:credit_note, %CreditNote{} = credit_note, locale) do
    %{
      title: ~t"Email credit note",
      submit_label: ~t"Send credit note",
      to: credit_note.invoice.buyer_email,
      last_sent: credit_note.sent_at && Format.datetime(credit_note.sent_at, locale)
    }
  end

  def text(kind, %Order{} = order, locale) do
    {title, submit_label, last_sent_at} =
      case kind do
        :order_details -> {~t"Email order details", ~t"Send order details", order.order_details_emailed_at}
        :receipt -> {~t"Email receipt", ~t"Send receipt", order.receipt_emailed_at}
        :fulfillment -> {~t"Email confirmation", ~t"Send confirmation", order.fulfillment_emailed_at}
        :payment_reminder -> {~t"Send payment reminder", ~t"Send reminder", nil}
        :gift_voucher -> {~t"Email gift voucher", ~t"Send gift voucher", order.receipt_emailed_at}
      end

    %{
      title: title,
      submit_label: submit_label,
      to: order.customer_email,
      last_sent: last_sent_at && Format.datetime(last_sent_at, locale)
    }
  end

  def text(kind, %CourseRegistration{} = registration, locale) do
    case kind do
      :confirmation ->
        %{
          title: ~t"Email confirmation",
          submit_label: ~t"Send confirmation",
          to: registration.email,
          last_sent:
            registration.confirmation_emailed_at && Format.datetime(registration.confirmation_emailed_at, locale)
        }

      :payment_reminder ->
        %{
          title: ~t"Send payment reminder",
          submit_label: ~t"Send reminder",
          to: registration.email,
          last_sent:
            registration.payment_link_emailed_at && Format.datetime(registration.payment_link_emailed_at, locale)
        }

      :payment_link ->
        last_sent_at = registration.payment_link_open? && registration.payment_link_emailed_at

        %{
          title: ~t"Email payment link",
          submit_label: ~t"Send payment link",
          to: registration.email,
          last_sent: last_sent_at && Format.datetime(last_sent_at, locale)
        }
    end
  end

  defp invoice_send_label(%{overdue?: true}), do: ~t"Send reminder"
  defp invoice_send_label(%{sent_at: nil}), do: ~t"Send invoice"
  defp invoice_send_label(_invoice), do: ~t"Resend invoice"
end
