defmodule EdenflowersWeb.Admin.InvoicesLive do
  @moduledoc "Standalone invoice register."
  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
  use Cinder.UrlSync
  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Payments.Invoice
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: ~t"Invoices", locale: Localize.get_locale())}

  def handle_params(params, uri, socket),
    do: {:noreply, Cinder.UrlSync.handle_params(params, uri, socket)}

  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Invoices"}>
          <:actions>
            <.button navigate={~p"/admin/invoices/new"} variant="primary" size="sm">{~t"New invoice"}</.button>
          </:actions>
        </.admin_page_header>
        <Cinder.collection
          id="invoices-table"
          resource={Invoice}
          action={:admin_list}
          actor={@current_user}
          query_opts={[load: [:status, :buyer, :overdue?, :amount_unpaid]]}
          url_state={@url_state}
          theme={EdenflowersWeb.Admin.CinderTheme}
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          click={fn invoice -> JS.navigate(~p"/admin/invoices/#{invoice.id}") end}
        >
          <:col :let={invoice} field="number" sort label={~t"Invoice"}>
            <.link navigate={~p"/admin/invoices/#{invoice.id}"} class="link font-semibold">
              {if invoice.number, do: to_string(invoice.number), else: ~t"Draft"}
            </.link>
          </:col>
          <:col :let={invoice} field="buyer" search label={~t"Customer"}>
            {invoice.buyer || ~t"Customer details needed"}
          </:col>
          <:col
            :let={invoice}
            field="status"
            label={~t"Status"}
            filter={[
              type: :select,
              label: ~t"Status",
              prompt: ~t"All",
              options: [{~t"Draft", :draft}, {~t"Unpaid", :open}, {~t"Paid", :paid}, {~t"Credited", :cancelled}]
            ]}
          >
            <.badge tone={status_tone(invoice.status, invoice.overdue?)}>
              {status_label(invoice.status, invoice.overdue?)}
            </.badge>
          </:col>
          <:col :let={invoice} field="due_date" sort label={~t"Due date"} class="max-sm:hidden">
            <span class="tabular-nums">{Format.date(invoice.due_date, @locale)}</span>
          </:col>
          <:col :let={invoice} field="amount" sort label={~t"Amount"} class="text-right tabular-nums">
            {if invoice.status == :draft, do: "—", else: Format.currency(invoice.amount, @locale)}
          </:col>
          <:col :let={invoice} field="amount_unpaid" label={~t"Balance"} class="text-right tabular-nums max-sm:hidden">
            {if invoice.status in [:draft, :cancelled], do: "—", else: Format.currency(invoice.amount_unpaid, @locale)}
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  def status_label(:draft, _), do: ~t"Draft"
  def status_label(:cancelled, _), do: ~t"Credited"
  def status_label(:paid, _), do: ~t"Paid"
  def status_label(:open, true), do: ~t"Overdue"
  def status_label(:open, _), do: ~t"Unpaid"
  def status_tone(:paid, _), do: :success
  def status_tone(:open, true), do: :error
  def status_tone(:open, _), do: :warning
  def status_tone(_, _), do: :neutral
end
