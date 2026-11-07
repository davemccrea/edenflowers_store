defmodule EdenflowersWeb.Admin.GiftVoucherSaleLive do
  @moduledoc """
  Where Jennie sells a Gift voucher in the shop. She lands on the sale's
  order page, whose Gift voucher card shows the code to write onto the gift
  card, and records the buyer's payment there.
  """
  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Orders.Order
  alias EdenflowersWeb.Admin.CustomerSearch

  @impl true
  def mount(_params, _session, socket) do
    form =
      Order
      |> AshPhoenix.Form.for_create(:sell_gift_voucher,
        actor: socket.assigns.current_user,
        params: %{"locale" => "sv-FI", "voucher_style" => "cream"}
      )
      |> to_form()

    {:ok,
     assign(socket, page_title: ~t"Sell gift voucher", form: form, customer_search_empty?: false, customer_term: "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@page_title} back={{~t"Orders", ~p"/admin/orders"}} sticky>
          <:actions>
            <.button type="submit" form="gift-voucher-form" variant="primary" size="sm">
              {~t"Sell voucher"}
            </.button>
          </:actions>
        </.admin_page_header>

        <.form
          for={@form}
          id="gift-voucher-form"
          phx-change="validate"
          phx-submit="save"
          class="max-w-2xl space-y-6"
        >
          <.form_section title={~t"Voucher"}>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input
                field={@form[:amount]}
                type="number"
                min="20"
                step="1"
                inputmode="numeric"
                label={~t"Amount (€)"}
                class="input w-full tabular-nums"
              />
              <.input
                field={@form[:locale]}
                type="select"
                label={~t"Language"}
                options={[{"Svenska", "sv-FI"}, {"Suomi", "fi"}, {"English", "en-GB"}]}
                class="select w-full"
              />
              <.input
                field={@form[:voucher_style]}
                type="select"
                label={~t"Style"}
                options={[
                  {~t"Signature", "cream"},
                  {~t"Christmas red", "christmas"},
                  {~t"Christmas green", "christmas_green"}
                ]}
                class="select w-full"
              />
              <.input
                field={@form[:recipient_name]}
                type="text"
                label={~t"Recipient name"}
                class="input w-full"
                autocapitalize="words"
              />
              <div class="sm:col-span-2">
                <.input
                  field={@form[:card_message]}
                  type="textarea"
                  rows="3"
                  label={~t"Message"}
                  maxlength={Edenflowers.Orders.Order.Checkout.voucher_message_length()}
                  class="textarea w-full"
                />
              </div>
            </div>
          </.form_section>

          <.form_section title={~t"Buyer"}>
            <.customer_picker field={@form[:customer_id]} empty?={@customer_search_empty?} focus="customer_focus" />
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div class="sm:col-span-2">
                <.input
                  field={@form[:customer_name]}
                  type="text"
                  label={~t"Name"}
                  class="input w-full"
                  autocapitalize="words"
                />
              </div>
              <.input
                field={@form[:customer_phone_number]}
                type="tel"
                label={~t"Phone"}
                class="input w-full"
                autocomplete="off"
              />
              <.input
                field={@form[:customer_email]}
                type="email"
                label={~t"Email"}
                class="input w-full"
                autocomplete="off"
              />
            </div>
          </.form_section>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("live_select_change", %{"id" => "customer-select", "text" => term}, socket),
    do: {:noreply, CustomerSearch.search(socket, term)}

  def handle_event("customer_focus", _params, socket), do: {:noreply, CustomerSearch.focus(socket)}

  def handle_event("validate", %{"form" => params}, socket) do
    form = socket.assigns.form
    params = CustomerSearch.prefill(params, form[:customer_id].value, socket.assigns.current_user)
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, sale} ->
        {:noreply,
         socket
         |> put_flash(:success, ~t"Gift voucher sold.")
         |> push_navigate(to: ~p"/admin/orders/#{sale.id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(form: form)
         |> put_flash(:error, ~t"The voucher wasn't sold. Check the fields marked below.")}
    end
  end
end
