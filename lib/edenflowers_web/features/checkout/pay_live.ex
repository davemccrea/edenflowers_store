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
         |> assign(:locale, Format.locale())
         |> assign(:email_form, email_form(order))
         |> PaymentLink.mount(order, params, fn -> load_order(token) end)
         |> assign_page_title()}

      _ ->
        {:ok, PaymentLink.broken_link(socket)}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :paid?, assigns.payable.paid?)

    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-xl">
          <.flower
            name="flower-30"
            class={["text-primary/70 mb-6 h-12 w-12", if(@paid?, do: "flower-bloom"), if(@returned_from_stripe? and @payable.payment_link_open?, do: "flower-waiting")]}
          />

          <%= cond do %>
            <% @payable.fulfillment_status == :cancelled -> %>
              <.heading reference={@payable.order_reference}>{~t"Order cancelled"}</.heading>
              <p class="leading-relaxed" data-testid="pay-cancelled">
                {~t"This order has been cancelled, so there is nothing to pay. If you have any questions, just get in touch."}
              </p>
            <% @payable.refunded? -> %>
              <.heading reference={@payable.order_reference}>{~t"Order refunded"}</.heading>
              <p class="leading-relaxed" data-testid="pay-refunded">
                {~t"This order has been refunded, so there is nothing to pay. If you have any questions, just get in touch."}
              </p>
            <% @paid? -> %>
              <.heading reference={@payable.order_reference} data-testid="pay-paid">
                {if @payable.customer_first_name,
                  do: ~t"Thank you, #{first_name = @payable.customer_first_name}.",
                  else: ~t"Thank you"}
              </.heading>
              <p :if={@payable.fulfillment_status == :fulfilled} class="leading-relaxed" data-testid="pay-thanks">
                {~t"I hope you're happy with it."}
              </p>
            <% @returned_from_stripe? -> %>
              <.heading reference={@payable.order_reference}>{~t"Thank you"}</.heading>
              <p role="status" class="leading-relaxed" data-testid="pay-confirming">
                {~t"Confirming your payment… You'll get a receipt by email once it's done."}
              </p>
            <% true -> %>
              <.heading reference={@payable.order_reference}>{~t"Pay for your order"}</.heading>
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

          <section class="mt-8" aria-label={~t"Order #{reference = @payable.order_reference}"}>
            <p
              :if={
                @payable.fulfillment_status != :cancelled and not @payable.refunded? and
                  not (@paid? and @payable.fulfillment_status == :fulfilled)
              }
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

            <dl class="border-base-content/12 border-t pt-2 text-base">
              <div
                :for={line_item <- @payable.line_items}
                class="flex justify-between gap-4 py-1"
              >
                <dt><span class="tabular-nums">{line_item.quantity} ×</span> {Format.line_item_name(line_item)}</dt>
                <dd class="tabular-nums">{Format.currency(line_item.subtotal, @locale)}</dd>
              </div>
              <div
                :if={@payable.fulfillment_fee && Decimal.positive?(@payable.fulfillment_fee)}
                class="flex justify-between gap-4 py-1"
              >
                <dt>{~t"Delivery"}</dt>
                <dd class="tabular-nums">{Format.currency(@payable.fulfillment_fee, @locale)}</dd>
              </div>
              <div class="border-base-content/12 mt-2 flex justify-between gap-4 border-t pt-3 pb-1 font-semibold">
                <dt>{if @paid?, do: ~t"Total paid", else: ~t"Total"}</dt>
                <dd class="tabular-nums" data-testid="pay-total">
                  {Format.currency(if(@paid?, do: @payable.amount_held, else: @payable.grand_total), @locale)}
                </dd>
              </div>
              <div :if={Decimal.positive?(@payable.amount_held) and not @paid?} class="flex justify-between gap-4 py-1">
                <dt>{~t"Paid so far"}</dt>
                <dd class="tabular-nums">{Format.currency(@payable.amount_held, @locale)}</dd>
              </div>
              <div
                :if={Decimal.positive?(@payable.amount_paid) && @payable.payment_link_open?}
                class="flex justify-between gap-4 py-1 font-semibold"
              >
                <dt>{~t"Left to pay"}</dt>
                <dd class="tabular-nums" data-testid="pay-balance">{Format.currency(@payable.balance, @locale)}</dd>
              </div>
              <div :if={Decimal.negative?(@payable.balance)} class="flex justify-between gap-4 py-1">
                <dt>{~t"To be refunded"}</dt>
                <dd class="tabular-nums" data-testid="pay-refund-due">
                  {Format.currency(Decimal.abs(@payable.balance), @locale)}
                </dd>
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

          <.button navigate={~q"/#{language}/store"} variant="text" class="mt-10">{~t"Back to the shop"}</.button>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  attr :reference, :string, required: true
  attr :rest, :global
  slot :inner_block, required: true

  defp heading(assigns) do
    ~H"""
    <hgroup class="mb-6">
      <h1 class="page-title" {@rest}>{render_slot(@inner_block)}</h1>
      <p class="text-base-content/70 mt-2 text-sm">{~t"Order #{reference = @reference}"}</p>
    </hgroup>
    """
  end

  @impl true
  def handle_event("validate_email", %{"form" => params}, socket) do
    {:noreply, assign(socket, :email_form, AshPhoenix.Form.validate(socket.assigns.email_form, params))}
  end

  def handle_event("pay", params, %{assigns: %{email_form: form}} = socket) when not is_nil(form) do
    case AshPhoenix.Form.submit(form, params: Map.get(params, "form", %{})) do
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
    do: {:noreply, socket |> PaymentLink.paid() |> assign_page_title()}

  defp assign_page_title(socket) do
    order = socket.assigns.payable

    title =
      cond do
        order.fulfillment_status == :cancelled -> ~t"Order cancelled"
        order.refunded? -> ~t"Order refunded"
        order.paid? or socket.assigns.returned_from_stripe? -> ~t"Thank you for your order"
        true -> ~t"Pay for your order"
      end

    assign(socket, :page_title, title)
  end

  defp email_form(%{customer_email: nil} = order) do
    order
    |> AshPhoenix.Form.for_update(:add_customer_email, actor: system_actor())
    |> to_form()
  end

  defp email_form(_order), do: nil

  defp load_order(token), do: Orders.get_order_by_payment_link_token(token, authorize?: false)
end
