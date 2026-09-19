defmodule EdenflowersWeb.Checkout.OrderLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Receipt

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  # `@order` is taken by the PutOrder hook (the cart), hence `@placed_order`.
  def mount(%{"id" => id}, session, socket) do
    user = socket.assigns.current_user
    guest_order_id = session["guest_order_id"]

    case get_order(id, guest_order_id, user) do
      {:ok, %{state: :placed} = order} ->
        {:ok, assign_placed_order(socket, order)}

      # Stripe can redirect here before its webhook has placed the order. Anyone
      # can read an order still in checkout, so only its owner may wait for it.
      {:ok, %{state: :payment} = order}
      when id == guest_order_id or (not is_nil(user) and order.user_id == user.id) ->
        if connected?(socket), do: Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:placed:#{order.id}")
        {:ok, assign(socket, placed_order: nil, order_id: order.id)}

      _ when is_nil(user) ->
        {:ok, redirect(socket, to: ~p"/sign-in?return_to=/order/#{id}")}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Order not found.")
         |> push_navigate(to: ~p"/")}
    end
  end

  # Only the order's owner subscribes, in mount.
  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:placed:" <> _}, socket) do
    order = Orders.get_order_by_id!(socket.assigns.order_id, authorize?: false)
    {:noreply, assign_placed_order(socket, order)}
  end

  # A guest is granted the order their session's cart became (see `InitStore` and
  # `CheckoutCompleteController`); everyone else goes through the order's read policy.
  def get_order(id, guest_order_id, _user) when id == guest_order_id,
    do: Orders.get_order_by_id(id, authorize?: false)

  def get_order(id, _guest_order_id, user), do: Orders.get_order_by_id(id, actor: user)

  defp assign_placed_order(socket, order) do
    {:ok, order} = Receipt.load_for_receipt(order)

    socket
    |> assign(:page_title, ~t"Order #{order.order_reference}")
    |> assign(:placed_order, order)
  end

  def render(%{placed_order: nil} = assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title">{~t"Confirming your payment…"}</h1>
        <p class="text-base-content/70 mt-4" data-testid="order-pending">
          {~t"This usually takes a few seconds. You'll also get a confirmation email once it's done."}
        </p>
      </.container>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <p class="eyebrow text-base-content/70 mb-5">{~t"Thank you for your order"}</p>
        <h1 class="page-title">{@placed_order.order_reference}</h1>
        <p class="text-base-content/70 mt-4 max-w-prose">
          {~t"A confirmation with your receipt has been sent to #{@placed_order.customer_email}."}
        </p>

        <div class="mt-10 grid gap-10 md:grid-cols-2">
          <section class="flex flex-col gap-4" data-testid="order-fulfillment">
            <p class="eyebrow text-base-content/70">{fulfillment_label(@placed_order.fulfillment_method)}</p>
            <p>{Format.date(@placed_order.fulfillment_date, @placed_order.locale)}</p>
            <p :if={@placed_order.fulfillment_method == :delivery}>{@placed_order.delivery_address}</p>
            <p :if={@placed_order.gift && @placed_order.recipient_name}>
              {~t"For #{@placed_order.recipient_name}"}
            </p>
            <blockquote
              :if={@placed_order.card_message}
              class="border-base-content/20 whitespace-pre-wrap border-l-2 pl-3 italic"
            >
              {@placed_order.card_message}
            </blockquote>
          </section>

          <section class="flex flex-col gap-2 text-base" data-testid="order-summary">
            <p class="eyebrow text-base-content/70 mb-2">{~t"Summary"}</p>

            <div :for={item <- @placed_order.line_items} class="flex items-baseline justify-between gap-4">
              <span>{item.quantity} × {item.product_name}</span>
              <span class="tabular-nums">{Format.currency(item.total, @placed_order.locale)}</span>
            </div>

            <div class="border-base-content/12 my-2 border-t"></div>

            <div class="flex items-baseline justify-between">
              <span>{fulfillment_label(@placed_order.fulfillment_method)}</span>
              <span class="tabular-nums">{Format.currency(@placed_order.fulfillment_fee || 0, @placed_order.locale)}</span>
            </div>
            <div :if={@placed_order.promotion_applied?} class="flex items-baseline justify-between">
              <span>{~t"Discount"}</span>
              <span class="text-success tabular-nums">
                - {Format.currency(@placed_order.discount, @placed_order.locale)}
              </span>
            </div>
            <div class="flex items-baseline justify-between">
              <span>{~t"Incl. VAT"}</span>
              <span class="tabular-nums">{Format.currency(@placed_order.tax, @placed_order.locale)}</span>
            </div>
            <div class="mt-3 flex items-baseline justify-between font-semibold">
              <span>{~t"Total"}</span>
              <span class="tabular-nums">{Format.currency(@placed_order.grand_total, @placed_order.locale)}</span>
            </div>

            <.button href={~p"/order/#{@placed_order.id}/receipt"} variant="secondary" class="mt-6 w-fit">
              <.icon name="hero-arrow-down-tray" class="h-4 w-4" />
              {~t"Download receipt"}
            </.button>
          </section>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp fulfillment_label(:delivery), do: ~t"Delivery"
  defp fulfillment_label(_), do: ~t"Pickup"
end
