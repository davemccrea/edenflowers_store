defmodule EdenflowersWeb.Checkout.PayLive do
  @moduledoc """
  The page behind a custom order's payment link. The token in the URL is the
  only thing that grants access, so the page shows what the customer agreed
  with Jennie and never the florist note.

  It always speaks the order's language, which Jennie chose when she took the
  order, rather than the browser's.
  """
  use EdenflowersWeb, :live_view

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Payments

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  defp stripe_publishable_key, do: Application.get_env(:edenflowers, :stripe_publishable_key)

  # `@order` is taken by the PutOrder hook (the cart), hence `@shown_order`.
  def mount(%{"token" => token} = params, _session, socket) do
    case Orders.get_order_by_payment_link_token(token, authorize?: false) do
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
         |> assign(:token, token)
         |> assign(:returned_from_stripe?, params["redirect_status"] == "succeeded")
         |> assign(:shown_order, order)
         |> assign_payment()
         |> maybe_flash_failed_payment(params)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, ~t"This payment link doesn't work. Please get in touch.")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("pay", _params, socket) do
    {:noreply, push_event(socket, "stripe:process_payment", %{})}
  end

  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error("Stripe client error for order #{socket.assigns.shown_order.id}: #{message}: #{inspect(details)}")

    {:noreply,
     put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please refresh the page and try again.")}
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:paid:" <> _}, socket) do
    {:ok, order} = Orders.get_order_by_payment_link_token(socket.assigns.token, authorize?: false)
    {:noreply, socket |> assign(:shown_order, order) |> assign(:client_secret, nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-xl">
          <.flower name="flower-30" class="text-primary/70 mb-8 h-16 w-16" />

          <%= cond do %>
            <% @shown_order.fulfillment_status == :cancelled -> %>
              <h1 class="page-title mb-6">{~t"Order cancelled"}</h1>
              <p class="leading-relaxed" data-testid="pay-cancelled">
                {~t"This order has been cancelled, so there is nothing to pay. Get in touch if that's a surprise."}
              </p>
            <% @shown_order.payment_status == :paid -> %>
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
          <% end %>

          <section class="mt-10" aria-labelledby="order-summary-heading">
            <h2 id="order-summary-heading" class="section-title mb-4">
              {~t"Order #{reference = @shown_order.order_reference}"}
            </h2>

            <p class="mb-4 leading-relaxed" data-testid="pay-fulfillment">
              <%= if @shown_order.fulfillment_method == :delivery do %>
                {~t"Delivery on #{date = Format.weekday_date(@shown_order.fulfillment_date, @locale)} to #{address = @shown_order.delivery_address}"}
              <% else %>
                {~t"Ready to collect at the shop on #{date = Format.weekday_date(@shown_order.fulfillment_date, @locale)}"}
              <% end %>
              <span :if={@shown_order.gift && @shown_order.recipient_name} class="block">
                {~t"For #{recipient = @shown_order.recipient_name}"}
              </span>
            </p>

            <dl class="border-base-content/12 border-t text-base">
              <div
                :for={line_item <- @shown_order.line_items}
                class="border-base-content/12 flex justify-between gap-4 border-b py-3"
              >
                <dt><span class="tabular-nums">{line_item.quantity} ×</span> {line_item.product_name}</dt>
                <dd class="tabular-nums">{Format.currency(line_item.subtotal, @locale)}</dd>
              </div>
              <div
                :if={@shown_order.fulfillment_fee && Decimal.positive?(@shown_order.fulfillment_fee)}
                class="border-base-content/12 flex justify-between gap-4 border-b py-3"
              >
                <dt>{~t"Delivery"}</dt>
                <dd class="tabular-nums">{Format.currency(@shown_order.fulfillment_fee, @locale)}</dd>
              </div>
              <div class="flex justify-between gap-4 py-3 font-semibold">
                <dt>{~t"Total"}</dt>
                <dd class="tabular-nums" data-testid="pay-total">{Format.currency(@shown_order.grand_total, @locale)}</dd>
              </div>
            </dl>
          </section>

          <section :if={payable?(@shown_order) and not @returned_from_stripe?} class="mt-10" aria-label={~t"Payment"}>
            <form
              :if={@client_secret}
              id="pay-form"
              phx-hook="Stripe"
              phx-submit="pay"
              data-client-secret={@client_secret}
              data-publishable-key={stripe_publishable_key()}
              data-return-url={url(~p"/pay/#{@token}")}
              data-billing-name={@shown_order.customer_name}
              data-billing-email={@shown_order.customer_email}
              data-billing-phone={@shown_order.customer_phone_number}
              data-stripe-loading={JS.set_attribute({"disabled", "true"}, to: "#payment-button")}
              data-stripe-ready={JS.remove_attribute("disabled", to: "#payment-button")}
              class="flex flex-col gap-4"
            >
              <div phx-update="ignore" id="payment-element"></div>
              <p phx-update="ignore" id="stripe-error-message" role="alert" class="text-error"></p>

              <.form_button disabled={true} id="payment-button">
                {~t"Pay"} {Format.currency(@shown_order.grand_total, @locale)}
              </.form_button>
            </form>

            <p :if={@payment_unavailable?} class="text-error" data-testid="stripe-unavailable">
              {~t"Payment is temporarily unavailable. Please try again in a moment."}
            </p>
          </section>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp payable?(order), do: order.payment_status != :paid and order.fulfillment_status != :cancelled

  # Stripe is only touched once the page is live, so a crawler or a link
  # preview never creates a PaymentIntent. Back from Stripe, the payment is
  # in flight and its PaymentIntent must not change.
  defp assign_payment(%{assigns: %{shown_order: order}} = socket) do
    if connected?(socket) and payable?(order) and not socket.assigns.returned_from_stripe? do
      case client_secret(order) do
        {:ok, client_secret} ->
          assign(socket, client_secret: client_secret, payment_unavailable?: false)

        {:error, reason} ->
          Logger.error("Could not set up payment for order #{order.id}: #{inspect(reason)}")
          assign(socket, client_secret: nil, payment_unavailable?: true)
      end
    else
      assign(socket, client_secret: nil, payment_unavailable?: false)
    end
  end

  # Jennie may have changed the order since the PaymentIntent was made, and the
  # link always charges the current total.
  defp client_secret(order) do
    with :ok <- sync_amount(order),
         {:ok, _order, client_secret} <- Payments.setup(order, system_actor()) do
      {:ok, client_secret}
    end
  end

  defp sync_amount(%{payment_intent_id: nil}), do: :ok

  defp sync_amount(order) do
    case Payments.update_amount(order) do
      {:ok, _payment_intent} -> :ok
      error -> error
    end
  end

  # A redirect-based method (MobilePay) comes back with `redirect_status=failed`
  # when the customer cancels or is declined in the app.
  defp maybe_flash_failed_payment(socket, %{"redirect_status" => "failed"}) do
    put_flash(socket, :error, ~t"Your payment didn't go through. Please try again or choose another payment method.")
  end

  defp maybe_flash_failed_payment(socket, _params), do: socket
end
