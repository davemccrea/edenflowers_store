defmodule EdenflowersWeb.Checkout.OrderLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Format
  alias Edenflowers.Orders

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  # `@order` is taken by the PutOrder hook (the cart), hence `@shown_order`.
  def mount(%{"id" => id}, session, socket) do
    user = socket.assigns.current_user
    guest_order_id = session["guest_order_id"]

    case get_order(id, guest_order_id, user) do
      {:ok, %{state: :placed} = order} ->
        {:ok, assign_order(socket, order)}

      # Stripe can redirect here before its webhook has placed the order. The
      # order already carries everything this page shows, so it renders straight
      # away and only the payment line waits. Anyone can read an order still in
      # checkout, so only its owner may wait for it.
      {:ok, %{state: state} = order}
      when state in [:payment, :confirming_payment] and
             (id == guest_order_id or (not is_nil(user) and order.user_id == user.id)) ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:placed:#{order.id}")
        end

        {:ok, assign_order(socket, order)}

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
    order = Orders.get_order_by_id!(socket.assigns.shown_order.id, authorize?: false)
    {:noreply, assign_order(socket, order)}
  end

  # A guest is granted the order their session's cart became (see `InitStore` and
  # `CheckoutCompleteController`); everyone else goes through the order's read policy.
  def get_order(id, guest_order_id, _user) when id == guest_order_id,
    do: Orders.get_order_by_id(id, authorize?: false)

  def get_order(id, _guest_order_id, user), do: Orders.get_order_by_id(id, actor: user)

  defp assign_order(socket, order) do
    {:ok, order} = Ash.load(order, :customer_first_name, authorize?: false)

    socket
    |> assign(:page_title, ~t"Thank you for your order")
    |> assign(:shown_order, order)
    |> assign(:paid?, order.state == :placed)
    |> assign(:first_name, order.customer_first_name)
    |> assign(:date, Format.weekday_date(order.fulfillment_date, Format.locale()))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-xl">
          <.flower name="flower-30" class="text-primary/70 mb-8 h-16 w-16" />
          <div id="order-status">
            <h1 :if={@first_name} class="page-title">{~t"Thank you, #{@first_name}."}</h1>
            <h1 :if={!@first_name} class="page-title">{~t"Thank you for your order"}</h1>

            <p class="font-serif text-balance mt-6 text-2xl leading-snug" data-testid="order-fulfillment">
              <%= if @shown_order.fulfillment_method == :delivery do %>
                {~t"I'll deliver your order on #{@date}."}
              <% else %>
                {~t"Your order will be ready at the shop on #{@date}."}
              <% end %>
            </p>
            <p
              :if={@shown_order.fulfillment_method == :pickup && @shown_order.recipient_phone_number}
              class="font-serif text-base-content/80 mt-1 text-xl leading-snug"
            >
              {~t"I'll send a text message when it's ready."}
            </p>
          </div>

          <%!-- A live region, so the swap from confirming to received is announced. --%>
          <p
            id="payment-status"
            role="status"
            class="text-base-content/70 mt-6 text-sm"
            data-testid={if @paid?, do: "order-paid", else: "order-pending"}
          >
            <%= if @paid? do %>
              <.icon name="hero-check-circle" class="text-primary size-4 align-[-0.2em]" />
              {~t"Payment received. A confirmation email is on its way."}
            <% else %>
              {~t"Confirming your payment… You'll get a confirmation email once it's done."}
            <% end %>
          </p>

          <figure
            :if={@shown_order.card_message}
            class="bg-cream text-cream-content mt-10 max-w-sm px-7 py-6"
            data-testid="order-card"
          >
            <figcaption :if={@shown_order.gift && @shown_order.recipient_name} class="mb-3 text-sm">
              {~t"For #{@shown_order.recipient_name}"}
            </figcaption>
            <blockquote class="font-serif whitespace-pre-wrap text-xl italic leading-snug" phx-no-format>{@shown_order.card_message}</blockquote>
          </figure>

          <div class="mt-12 flex flex-wrap items-center gap-x-8 gap-y-4">
            <.button
              :if={@paid?}
              href={~p"/order/#{@shown_order.id}/receipt"}
              target="_blank"
              rel="noopener"
              variant="secondary"
              size="lg"
            >
              {~t"View receipt"}
              <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            </.button>
            <.button navigate={~p"/store"} variant="text">{~t"Back to the shop"}</.button>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end
end
