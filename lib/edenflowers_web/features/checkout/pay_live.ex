defmodule EdenflowersWeb.Checkout.PayLive do
  @moduledoc """
  The page behind a custom order's payment link. The token in the URL is the
  only thing that grants access, so the page shows what the customer agreed
  with Jennie and never the florist note.

  It always speaks the order's language, which Jennie chose when she took the
  order, rather than the browser's.
  """
  use EdenflowersWeb, :live_view

  import Edenflowers.Actors

  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias EdenflowersWeb.PaymentLink

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    case load_order(token) do
      {:ok, order} ->
        Localize.Plug.put_locale_from_session(
          %{Localize.Plug.PutLocale.session_key() => order.locale},
          gettext: EdenflowersWeb.Gettext
        )

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:paid:#{order.id}")
        end

        {:ok,
         socket
         |> assign(:page_title, ~t"Pay for your order")
         |> assign(:locale, Format.locale())
         |> assign(:email_form, email_form(order))
         |> PaymentLink.mount(order, params, fn -> load_order(token) end)}

      _ ->
        {:ok, PaymentLink.broken_link(socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-xl">
          <.flower name="flower-30" class="text-primary/70 mb-8 h-16 w-16" />

          <%= cond do %>
            <% @payable.fulfillment_status == :cancelled -> %>
              <h1 class="page-title mb-6">{~t"Order cancelled"}</h1>
              <p class="leading-relaxed" data-testid="pay-cancelled">
                {~t"This order has been cancelled, so there is nothing to pay. If you have any questions, just get in touch."}
              </p>
            <% @payable.refunded? -> %>
              <h1 class="page-title mb-6">{~t"Order refunded"}</h1>
              <p class="leading-relaxed" data-testid="pay-refunded">
                {~t"This order has been refunded, so there is nothing to pay. If you have any questions, just get in touch."}
              </p>
            <% not @payable.payment_link_open? -> %>
              <h1 class="page-title mb-6">{~t"Thank you"}</h1>
              <p class="leading-relaxed" data-testid="pay-paid">
                {~t"This order is paid."}
              </p>
            <% @returned_from_stripe? -> %>
              <h1 class="page-title mb-6">{~t"Thank you"}</h1>
              <p role="status" class="leading-relaxed" data-testid="pay-confirming">
                {~t"Confirming your payment… You'll get a receipt by email once it's done."}
              </p>
            <% true -> %>
              <h1 class="page-title mb-6">{~t"Pay for order #{reference = @payable.order_reference}"}</h1>
              <p :if={@payable.subscription_id} class="leading-relaxed" data-testid="pay-subscription">
                {~t"This order is part of your subscription. Paying for it restarts the subscription if it's on hold."}
                {~t"It doesn't change the card your later deliveries are charged to."}
                <.link
                  navigate={~p"/account/subscriptions/#{@payable.subscription_id}/card"}
                  class="link-underline-hover text-primary"
                >
                  {~t"Update your card"}
                </.link>
              </p>
          <% end %>

          <section class="mt-10" aria-label={~t"Order #{reference = @payable.order_reference}"}>
            <h2 :if={not awaiting_payment?(@payable, @returned_from_stripe?)} class="section-title mb-4">
              {~t"Order #{reference = @payable.order_reference}"}
            </h2>

            <p
              :if={@payable.fulfillment_status != :cancelled}
              class="mb-4 leading-relaxed"
              data-testid="pay-fulfillment"
            >
              <%= cond do %>
                <% @payable.fulfillment_status == :fulfilled and @payable.fulfillment_method == :delivery -> %>
                  {~t"Your order has been delivered. I hope you're happy with it."}
                <% @payable.fulfillment_status == :fulfilled -> %>
                  {~t"Your order has been collected. I hope you're happy with it."}
                <% @payable.fulfillment_method == :delivery -> %>
                  {~t"Delivery on #{date = Format.weekday_date(@payable.fulfillment_date, @locale)} to #{address = @payable.delivery_address}"}
                <% true -> %>
                  {~t"Ready to collect at the shop on #{date = Format.weekday_date(@payable.fulfillment_date, @locale)}"}
              <% end %>
              <span :if={@payable.gift && @payable.recipient_name} class="block">
                {~t"For #{recipient = @payable.recipient_name}"}
              </span>
            </p>

            <dl class="border-base-content/12 border-t text-base">
              <div
                :for={line_item <- @payable.line_items}
                class="border-base-content/12 flex justify-between gap-4 border-b py-3"
              >
                <dt><span class="tabular-nums">{line_item.quantity} ×</span> {Format.line_item_name(line_item)}</dt>
                <dd class="tabular-nums">{Format.currency(line_item.subtotal, @locale)}</dd>
              </div>
              <div
                :if={@payable.fulfillment_fee && Decimal.positive?(@payable.fulfillment_fee)}
                class="border-base-content/12 flex justify-between gap-4 border-b py-3"
              >
                <dt>{~t"Delivery"}</dt>
                <dd class="tabular-nums">{Format.currency(@payable.fulfillment_fee, @locale)}</dd>
              </div>
              <div class="flex justify-between gap-4 py-3 font-semibold">
                <dt>{~t"Total"}</dt>
                <dd class="tabular-nums" data-testid="pay-total">{Format.currency(@payable.grand_total, @locale)}</dd>
              </div>
              <div :if={Decimal.positive?(@payable.amount_paid)} class="flex justify-between gap-4 py-3">
                <dt>{~t"Paid so far"}</dt>
                <dd class="tabular-nums">{Format.currency(@payable.amount_paid, @locale)}</dd>
              </div>
              <div
                :if={Decimal.positive?(@payable.amount_paid) && @payable.payment_link_open?}
                class="flex justify-between gap-4 py-3 font-semibold"
              >
                <dt>{~t"Left to pay"}</dt>
                <dd class="tabular-nums" data-testid="pay-balance">{Format.currency(@payable.balance, @locale)}</dd>
              </div>
            </dl>
          </section>

          <PaymentLink.payment_form
            payable={@payable}
            returned_from_stripe?={@returned_from_stripe?}
            locale={@locale}
            billing_name={@payable.customer_name}
            billing_email={@payable.customer_email}
            billing_phone={@payable.customer_phone_number}
            email_field={@email_form && @email_form[:customer_email]}
          />
        </div>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate_email", %{"form" => params}, socket) do
    {:noreply, assign(socket, :email_form, AshPhoenix.Form.validate(socket.assigns.email_form, params))}
  end

  def handle_event("pay", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.email_form, params: params) do
      {:ok, _order} -> handle_event("pay", %{}, assign(socket, :email_form, nil))
      {:error, form} -> {:noreply, assign(socket, :email_form, form)}
    end
  end

  def handle_event("pay", _params, socket) do
    {:noreply, PaymentLink.pay(socket, ~t"The order changed. Please try again.")}
  end

  def handle_event("stripe:error", params, socket), do: {:noreply, PaymentLink.stripe_error(socket, params)}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:paid:" <> _}, socket),
    do: {:noreply, PaymentLink.paid(socket)}

  defp email_form(%{customer_email: nil} = order) do
    order
    |> AshPhoenix.Form.for_update(:add_customer_email, actor: system_actor())
    |> to_form()
  end

  defp email_form(_order), do: nil

  # The "Pay for order …" heading already names the order, so the summary skips its own.
  defp awaiting_payment?(payable, returned_from_stripe?) do
    payable.fulfillment_status != :cancelled and payable.payment_link_open? and not returned_from_stripe?
  end

  defp load_order(token), do: Orders.get_order_by_payment_link_token(token, authorize?: false)
end
