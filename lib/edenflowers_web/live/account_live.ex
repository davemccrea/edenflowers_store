defmodule EdenflowersWeb.AccountLive do
  use EdenflowersWeb, :live_view

  alias Edenflowers.Store.Order

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_required}

  def mount(_params, _session, socket) do
    orders =
      Order.get_all_completed!(
        actor: socket.assigns.current_user,
        load: [:grand_total],
        query: [sort: [ordered_at: :desc]]
      )

    {:ok, assign(socket, orders: orders)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title mb-16 md:mb-20">{~t"Your account"}</h1>

        <section class="max-w-3xl">
          <h2 class="section-title mb-6">{~t"Order history"}</h2>

          <ul :if={Enum.any?(@orders)} class="border-base-content/12 divide-base-content/12 divide-y border-t border-b">
            <li :for={order <- @orders} class="py-5">
              <.link
                navigate={~p"/order/#{order.id}"}
                class="group flex flex-col gap-1 sm:grid-cols-[1fr_auto_auto_auto] sm:grid sm:items-baseline sm:gap-6"
              >
                <span class="link-underline-hover-nav font-medium group-hover:text-base-content/70">
                  {order.order_reference}
                </span>
                <span class="text-base-content/70 text-sm tabular-nums">
                  {format_ordered_at(order.ordered_at)}
                </span>
                <span class="text-sm">
                  <.order_status_badge status={order.fulfillment_status} />
                </span>
                <span class="tabular-nums sm:text-right">
                  {Edenflowers.Utils.format_money(order.grand_total)}
                </span>
              </.link>
            </li>
          </ul>

          <p :if={Enum.empty?(@orders)} class="text-base-content/70">
            {~t"You haven't placed any orders yet."}
          </p>
        </section>
      </.container>
    </Layouts.app>
    """
  end

  attr :status, :atom, required: true

  defp order_status_badge(assigns) do
    ~H"""
    <span class={["inline-flex rounded-full px-2 py-0.5 text-xs", status_classes(@status)]}>
      {status_label(@status)}
    </span>
    """
  end

  defp status_label(:pending), do: ~t"Pending"
  defp status_label(:fulfilled), do: ~t"Fulfilled"

  defp status_classes(:pending), do: "bg-warning/15 text-warning-content"
  defp status_classes(:fulfilled), do: "bg-success/15 text-success-content"

  defp format_ordered_at(nil), do: ""

  defp format_ordered_at(%DateTime{} = dt) do
    locale = Localize.get_locale().cldr_locale_id
    Localize.Date.to_string!(DateTime.to_date(dt), locale: locale, format: :medium)
  end
end
