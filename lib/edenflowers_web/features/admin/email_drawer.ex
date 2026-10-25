defmodule EdenflowersWeb.Admin.EmailDrawer do
  @moduledoc """
  The state behind `EdenflowersWeb.Admin.Components.email_drawer`, shared by
  the order and course pages: opening it for a kind, rebuilding the preview as
  Jennie types, closing it, and what each kind is called. Sending stays on the
  page, because each kind has its own action and flash.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext

  import Phoenix.Component, only: [assign: 2, assign: 3, to_form: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Edenflowers.Courses.CourseRegistration
  alias Edenflowers.Format
  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Admin.DrawerPreview

  @doc """
  Opens the drawer for `kind`, previewing the email as it would go now.
  `assigns` is for what else the page tracks about it, like which booking.
  """
  def open(socket, kind, record, assigns \\ []) do
    kind = String.to_existing_atom(kind)

    socket
    |> assign(assigns)
    |> assign(email_kind: kind, email_form: to_form(%{"message" => ""}, as: :email))
    |> assign(:preview, DrawerPreview.build(kind, record, %{}))
    |> push_event("js-exec", %{to: "#email-drawer", attr: "phx-show"})
  end

  @doc "Closes the drawer, forgetting its form and preview."
  def close(socket, assigns \\ []) do
    socket
    |> assign(assigns)
    |> assign(email_form: nil, email_kind: nil, preview: nil)
  end

  @doc "Rebuilds the preview from the drawer's form as Jennie types."
  def validate(socket, params, record) do
    socket
    |> assign(email_form: to_form(params, as: :email))
    |> assign(:preview, DrawerPreview.build(socket.assigns.email_kind, record, params))
  end

  @doc "The drawer's heading, button and recipient for `kind`."
  def text(nil, _record, _locale), do: %{}
  def text(_kind, nil, _locale), do: %{}

  def text(kind, %Order{} = order, locale) do
    {title, submit_label, last_sent_at} =
      case kind do
        :order_details -> {~t"Email order details", ~t"Send order details", order.order_details_emailed_at}
        :receipt -> {~t"Email receipt", ~t"Send receipt", order.receipt_emailed_at}
        :fulfillment -> {~t"Email confirmation", ~t"Send confirmation", order.fulfillment_emailed_at}
        :payment_reminder -> {~t"Send payment reminder", ~t"Send reminder", nil}
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
end
