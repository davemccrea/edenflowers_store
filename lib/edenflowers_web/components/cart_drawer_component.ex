defmodule EdenflowersWeb.CartDrawerComponent do
  use EdenflowersWeb, :live_component

  alias Edenflowers.Store.Order

  def update(%{order: order} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:promo_code_form, fn -> build_promo_form(order) end)
      |> assign_new(:promo_open, fn -> false end)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.drawer
        id="cart-drawer"
        placement="right"
        label={gettext("Shopping cart")}
        class="bg-base-200 border-l-1 w-[80vw] flex h-full flex-col sm:w-[25rem]"
      >
        <header class="flex flex-row items-center justify-between pt-8 pr-4 pl-8">
          <h1 class="section-title">
            <%= if not is_nil(@order.total_items_in_cart) do %>
              {~t"Cart"} ({@order.total_items_in_cart})
            <% else %>
              {~t"Cart"}
            <% end %>
          </h1>

          <.icon_button aria_label={~t"Close cart"} phx-click={JS.exec("phx-hide", to: "#cart-drawer")}>
            <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
          </.icon_button>
        </header>

        <div class="flex flex-1 flex-col gap-6 overflow-y-auto p-8">
          <.live_component
            id="cart-line-items"
            module={EdenflowersWeb.LineItemsComponent}
            order={@order}
            link_product={true}
          />

          <.button
            :if={Enum.any?(@order.line_items)}
            navigate={~p"/checkout"}
            variant="primary"
            phx-click={JS.exec("phx-hide", to: "#cart-drawer")}
          >
            {~t"Checkout"}
          </.button>

          <div :if={Enum.any?(@order.line_items)} class="flex flex-col gap-3">
            <%= cond do %>
              <% @order.promotion_applied? -> %>
                <div class="flex items-baseline justify-between text-sm" data-testid="cart-drawer-promo-applied">
                  <span class="text-base-content/70">{~t"Promo code"}</span>
                  <button
                    type="button"
                    phx-click="clear_promo"
                    phx-target={@myself}
                    class="border-base-content/30 text-base-content/70 inline-flex cursor-pointer items-center gap-1 border px-2 py-0.5 text-xs hover:border-base-content hover:text-base-content"
                    data-testid="cart-drawer-promo-badge"
                  >
                    {@order.promotion.code} <.icon name="hero-x-mark" class="h-3 w-3" />
                  </button>
                </div>
              <% @promo_open -> %>
                <.form
                  id="cart-drawer-promo-form"
                  for={@promo_code_form}
                  phx-submit="update_promotional"
                  phx-target={@myself}
                  data-testid="cart-drawer-promo-form"
                >
                  <.input
                    style="button-addon"
                    field={@promo_code_form[:code]}
                    type="text"
                    button_text={~t"Apply"}
                    placeholder={~t"Promo code"}
                    data-testid="cart-drawer-promo-input"
                  />
                </.form>
              <% true -> %>
                <button
                  type="button"
                  phx-click="open_promo"
                  phx-target={@myself}
                  class="link-underline-hover-nav text-base-content/70 w-fit cursor-pointer text-sm"
                  data-testid="cart-drawer-promo-toggle"
                >
                  {~t"Have a promo code?"}
                </button>
            <% end %>
          </div>
        </div>
      </.drawer>
    </div>
    """
  end

  def handle_event("open_promo", _, socket) do
    {:noreply, assign(socket, promo_open: true)}
  end

  def handle_event("update_promotional", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.promo_code_form, params: params) do
      {:ok, _order} ->
        {:noreply,
         assign(socket,
           promo_code_form: build_promo_form(socket.assigns.order),
           promo_open: false
         )}

      {:error, promo_code_form} ->
        {:noreply, assign(socket, promo_code_form: promo_code_form, promo_open: true)}
    end
  end

  def handle_event("clear_promo", _, socket) do
    actor = socket.assigns[:current_user]
    Order.clear_promotion!(socket.assigns.order, actor: actor)

    {:noreply,
     assign(socket,
       promo_code_form: build_promo_form(socket.assigns.order),
       promo_open: false
     )}
  end

  defp build_promo_form(order) do
    order
    |> AshPhoenix.Form.for_update(:add_promotion_with_code)
    |> to_form()
  end
end
