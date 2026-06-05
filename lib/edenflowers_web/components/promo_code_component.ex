defmodule EdenflowersWeb.PromoCodeComponent do
  @moduledoc """
  Promo code affordance — collapsed link by default, expands to an input
  with Apply when the customer signals intent, and shows the applied
  code as a removable badge once a promotion is on the order.

  Mounted in both the cart drawer and the checkout right column. State
  (`promo_open`, the form) is owned by this component; the underlying
  `Order` mutations broadcast on `line_item:changed:<id>` so the parent
  LiveView reloads the order and passes it back in on the next render.
  """
  use EdenflowersWeb, :live_component

  alias Edenflowers.Store.Order

  def update(%{order: order} = assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:form, fn -> build_form(order) end)
      |> assign_new(:open, fn -> false end)

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%= cond do %>
        <% @order.promotion_applied? -> %>
          <div class="flex items-baseline justify-between text-sm" data-testid="promo-applied">
            <span class="text-base-content/70">{~t"Promo code"}</span>
            <button
              type="button"
              phx-click="clear_promo"
              phx-target={@myself}
              class="border-base-content/30 text-base-content/70 inline-flex cursor-pointer items-center gap-1 border px-2 py-0.5 text-xs hover:border-base-content hover:text-base-content"
              data-testid="promo-badge"
            >
              {@order.promotion_code} <.icon name="hero-x-mark" class="h-3 w-3" />
            </button>
          </div>
        <% @open -> %>
          <.form
            id={"#{@id}-form"}
            for={@form}
            phx-submit="apply_promo"
            phx-target={@myself}
            data-testid="promo-form"
          >
            <.input
              style="button-addon"
              field={@form[:code]}
              type="text"
              button_text={~t"Apply"}
              placeholder={~t"Promo code"}
              data-testid="promo-input"
              phx-mounted={JS.focus()}
            />
          </.form>
        <% true -> %>
          <button
            type="button"
            phx-click="open_promo"
            phx-target={@myself}
            class="link-underline-hover-nav text-base-content/70 w-fit cursor-pointer text-sm"
            data-testid="promo-toggle"
          >
            {~t"Have a promo code?"}
          </button>
      <% end %>
    </div>
    """
  end

  def handle_event("open_promo", _, socket) do
    {:noreply, assign(socket, open: true)}
  end

  def handle_event("apply_promo", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _order} ->
        {:noreply,
         assign(socket,
           form: build_form(socket.assigns.order),
           open: false
         )}

      {:error, form} ->
        {:noreply, assign(socket, form: form, open: true)}
    end
  end

  def handle_event("clear_promo", _, socket) do
    actor = socket.assigns[:current_user]
    Order.clear_promotion!(socket.assigns.order, actor: actor)

    {:noreply,
     assign(socket,
       form: build_form(socket.assigns.order),
       open: false
     )}
  end

  defp build_form(order) do
    order
    |> AshPhoenix.Form.for_update(:add_promotion_with_code)
    |> to_form()
  end
end
