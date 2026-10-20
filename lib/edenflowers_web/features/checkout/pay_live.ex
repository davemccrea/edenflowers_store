defmodule EdenflowersWeb.Checkout.PayLive do
  @moduledoc """
  The page behind a custom order's payment link. The token in the URL is the
  only thing that grants access, so the page shows what the customer agreed
  with Jennie and never the florist note.

  It always speaks the order's language, which Jennie chose when she took the
  order, rather than the browser's.
  """
  use EdenflowersWeb, :live_view

  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias EdenflowersWeb.PaymentLink

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    socket = assign(socket, alternates: alternates("/#{language}/pay/#{token}"), noindex: true)

    case load_order(token) do
      {:ok, order} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:paid:#{order.id}")
        end

        {:ok,
         socket
         |> assign(:page_title, ~t"Pay for your order")
         |> assign(:locale, Format.locale())
         |> PaymentLink.mount(order, params, fn -> load_order(token) end)}

      _ ->
        {:ok, PaymentLink.broken_link(socket)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      alternates={@alternates}
    >
      <.container>
        <div class="max-w-xl">
          <.flower name="flower-30" class="text-primary/70 mb-8 h-16 w-16" />

          <%= cond do %>
            <% @payable.fulfillment_status == :cancelled -> %>
              <h1 class="page-title mb-6">{~t"Order cancelled"}</h1>
              <p class="leading-relaxed" data-testid="pay-cancelled">
                {~t"This order has been cancelled, so there is nothing to pay. Get in touch if that's a surprise."}
              </p>
            <% not @payable.payment_link_open? -> %>
              <h1 class="page-title mb-6">{~t"Thank you"}</h1>
              <p class="leading-relaxed" data-testid="pay-paid">
                {~t"This order is paid. Thank you!"}
              </p>
            <% @returned_from_stripe? -> %>
              <h1 class="page-title mb-6">{~t"Thank you"}</h1>
              <p role="status" class="leading-relaxed" data-testid="pay-confirming">
                {~t"Confirming your payment… You'll get a receipt by email once it's done."}
              </p>
            <% true -> %>
              <h1 class="page-title mb-6">{~t"Pay for your order"}</h1>
              <p :if={@payable.subscription_id} class="leading-relaxed" data-testid="pay-subscription">
                {~t"This delivery is part of your subscription. Paying for it restarts the subscription if it's on hold."}
                {~t"It doesn't change the card your later deliveries are charged to."}
                <.link
                  navigate={~q"/#{language}/account/subscriptions/#{@payable.subscription_id}/card"}
                  class="link-underline-hover text-primary"
                >
                  {~t"Update your card"}
                </.link>
              </p>
          <% end %>

          <section class="mt-10" aria-labelledby="order-summary-heading">
            <h2 id="order-summary-heading" class="section-title mb-4">
              {~t"Order #{reference = @payable.order_reference}"}
            </h2>

            <p class="mb-4 leading-relaxed" data-testid="pay-fulfillment">
              <%= if @payable.fulfillment_method == :delivery do %>
                {~t"Delivery on #{date = Format.weekday_date(@payable.fulfillment_date, @locale)} to #{address = @payable.delivery_address}"}
              <% else %>
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
                <dt><span class="tabular-nums">{line_item.quantity} ×</span> {line_item.product_name}</dt>
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
            client_secret={@client_secret}
            payment_unavailable?={@payment_unavailable?}
            returned_from_stripe?={@returned_from_stripe?}
            locale={@locale}
            billing_name={@payable.customer_name}
            billing_email={@payable.customer_email}
            billing_phone={@payable.customer_phone_number}
          />
        </div>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("pay", _params, socket) do
    {:noreply, PaymentLink.pay(socket, ~t"The order changed. Please try again.")}
  end

  def handle_event("stripe:error", params, socket), do: {:noreply, PaymentLink.stripe_error(socket, params)}

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:paid:" <> _}, socket),
    do: {:noreply, PaymentLink.paid(socket)}

  defp load_order(token), do: Orders.get_order_by_payment_link_token(token, authorize?: false)
end
