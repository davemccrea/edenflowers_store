defmodule EdenflowersWeb.Checkout.OrderLive do
  @moduledoc """
  Customer order confirmation page. It can wait for a Stripe webhook to place an order still in payment and restricts access to its owner.
  """

  use EdenflowersWeb, :live_view

  require Logger

  import EdenflowersWeb.VoucherSkeleton, only: [voucher_skeleton: 1]

  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Payments.GiftVoucherPdf
  alias EdenflowersWeb.Analytics

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  # `@order` is taken by the PutOrder hook (the cart), hence `@shown_order`.
  @impl true
  def mount(%{"id" => id}, session, socket) do
    user = socket.assigns.current_user

    case get_order(id, session, user) do
      {:ok, %{state: :placed} = order} ->
        {:ok, assign_order(socket, order)}

      # Stripe can redirect here before its webhook has placed the order. The
      # order already carries everything this page shows, so it renders straight
      # away and only the payment line waits. Anyone can read an order still in
      # checkout, so only its owner may wait for it.
      {:ok, %{state: :payment} = order} ->
        if owner?(order, session, user),
          do: {:ok, wait_for_placement(socket, order)},
          else: not_found(socket, id, user)

      _ ->
        not_found(socket, id, user)
    end
  end

  defp wait_for_placement(socket, order) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:placed:#{order.id}")
    assign_order(socket, order)
  end

  defp not_found(socket, id, nil), do: {:ok, redirect(socket, to: ~p"/sign-in?return_to=/order/#{id}")}

  defp not_found(socket, _id, _user) do
    {:ok,
     socket
     |> put_flash(:error, ~t"Order not found.")
     |> push_navigate(to: ~q"/#{language}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      notice_bar={@notice_bar}
    >
      <.container>
        <div class="max-w-xl">
          <.flower
            name="flower-30"
            class={["text-primary/70 mb-6 h-12 w-12", if(@placed?, do: "flower-bloom", else: "flower-waiting")]}
          />
          <%!-- Covers <main>, so petals scroll with the page and stop at the footer. Under the fixed header. --%>
          <canvas
            :if={@placed?}
            id={"petals-#{@shown_order.id}"}
            phx-hook=".Petals"
            phx-update="ignore"
            data-petals={@shown_order.celebrated?}
            class="size-full pointer-events-none absolute inset-0"
            aria-hidden="true"
          ></canvas>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".Petals">
            // Petals fall once per order, so a reload or return visit stays calm. The flower blooms
            // once a session, like the home hero: the root layout's head script covers reloads,
            // and leaving marks <html> so live navigation back doesn't replay it either.
            export default {
              mounted() {
                try {
                  sessionStorage.setItem("order-bloomed", "1");
                  if (sessionStorage.getItem(this.el.id)) return;
                  sessionStorage.setItem(this.el.id, "1");
                } catch {
                  // Without storage there's no way to remember, so stay calm rather than replay.
                  return;
                }
                if (!this.el.hasAttribute("data-petals")) return;

                import("@/vendor/canvas-confetti.esm").then(({ default: confettiLib }) => {
                  const confetti = confettiLib.create(this.el, {
                    resize: true,
                    useWorker: true,
                  });
                  const shapes = [
                    // Cherry blossom: notched tip.
                    confettiLib.shapeFromPath({
                      path: "M0 18C-7 13-9 4-5-1L0 3L5-1C9 4 7 13 0 18Z",
                    }),
                    // Rose: broad and rounded.
                    confettiLib.shapeFromPath({
                      path: "M0 16C-9 12-10 2-5-2C-2-4 2-4 5-2C10 2 9 12 0 16Z",
                    }),
                  ];
                  const colors = ["#f2b8c1", "#eea7b2", "#e08896", "#d46f80", "#f0b088"];

                  // One petal at a time, each from its own slot across the top in shuffled order,
                  // over a few seconds and at varied speeds, so they fall apart rather than as one band.
                  const count = 36;
                  const slots = [...Array(count).keys()].sort(() => Math.random() - 0.5);
                  slots.forEach((slot, i) => {
                    setTimeout(() => {
                      confetti({
                        particleCount: 1,
                        origin: { x: (slot + Math.random()) / count, y: 0 },
                        angle: 270,
                        spread: 70,
                        startVelocity: 4,
                        gravity: 0.35 + Math.random() * 0.2,
                        drift: Math.random() - 0.5,
                        decay: 0.96,
                        ticks: 600,
                        scalar: 1.4 + Math.random() * 0.7,
                        shapes,
                        colors,
                        disableForReducedMotion: true,
                      });
                    }, i * 170);
                  });
                });
              },
              destroyed() {
                document.documentElement.classList.add("order-bloomed");
              },
            };
          </script>
          <div id="order-status">
            <h1 :if={@first_name} class="page-title">{~t"Thank you, #{@first_name}."}</h1>
            <h1 :if={!@first_name} class="page-title">{~t"Thank you for your order"}</h1>

            <p class="mt-6 leading-relaxed" data-testid="order-fulfillment">
              <%= cond do %>
                <% @shown_order.collect_voucher_card -> %>
                  {~t"Your gift voucher for #{name = @shown_order.recipient_name} will be emailed to you at #{email = @shown_order.customer_email}, ready to print or forward. A gift card with the voucher written on it can be collected at Minimossen from #{@date}."}
                <% @shown_order.gift_voucher_sale? -> %>
                  {~t"Your gift voucher for #{name = @shown_order.recipient_name} will be emailed to you at #{email = @shown_order.customer_email}, ready for you to print or forward."}
                <% @shown_order.fulfillment_method == :delivery -> %>
                  {~t"I'll deliver your order on #{@date}."}
                <% true -> %>
                  {~t"Your order will be ready to collect on #{@date}."}
              <% end %>
            </p>
            <p
              :if={@shown_order.fulfillment_method == :pickup && @shown_order.customer_phone_number}
              class="text-base-content/80 leading-relaxed"
            >
              {~t"I'll send a text message when it's ready."}
            </p>
          </div>

          <div :if={@next_delivery} class="mt-8" data-testid="order-subscription">
            <dl class="border-base-content/12 grid-cols-[auto_1fr] grid items-baseline gap-x-6 gap-y-3 border-y py-4">
              <dt class="eyebrow text-base-content/70">{~t"Subscription"}</dt>
              <dd>{EdenflowersWeb.Checkout.Fields.interval_label(@interval_weeks)}</dd>

              <dt class="eyebrow text-base-content/70">{~t"Next delivery"}</dt>
              <dd data-testid="order-next-delivery">{@next_delivery.date}</dd>

              <dt class="eyebrow text-base-content/70">{~t"Payment"}</dt>
              <dd class="tabular-nums" data-testid="order-next-charge">
                {~t"#{amount = @next_delivery.amount} on #{date = @next_delivery.charge_date}"}
              </dd>
            </dl>

            <p :if={!@current_user} class="text-base-content/70 mt-6">
              <.link navigate={~p"/sign-in"} class="link-underline-hover">
                {~t"Sign in with #{email = @shown_order.customer_email}"}
              </.link>
              {~t"to pause or cancel."}
            </p>
          </div>

          <div
            :if={@shown_order.gift_voucher_sale? && !@voucher_preview_error?}
            class="aspect-[210/148] relative mt-8 max-w-md shadow-sm"
            aria-busy={to_string(!@voucher_preview)}
            data-testid="order-voucher"
          >
            <.voucher_skeleton :if={!@voucher_preview} />
            <p :if={!@voucher_preview} class="sr-only" role="status">{~t"Loading preview…"}</p>
            <img
              :if={@voucher_preview}
              src={"data:image/png;base64," <> @voucher_preview}
              alt={~t"Preview of your gift voucher"}
              class="block h-full w-full"
            />
          </div>

          <figure
            :if={@shown_order.card_message && !@shown_order.gift_voucher_sale?}
            class="bg-cream text-cream-content mt-8 max-w-sm px-7 py-6"
            data-testid="order-card"
          >
            <figcaption :if={@shown_order.gift && @shown_order.recipient_name} class="mb-3 text-sm">
              {~t"For #{@shown_order.recipient_name}"}
            </figcaption>
            <blockquote class="font-serif whitespace-pre-wrap text-xl italic leading-snug" phx-no-format>{@shown_order.card_message}</blockquote>
          </figure>

          <div class="mt-10 flex flex-wrap items-center gap-x-8 gap-y-4">
            <div :if={@shown_order.receipt_available? || (@next_delivery && @current_user)} class="flex flex-wrap gap-3">
              <.button
                :if={@shown_order.receipt_available?}
                href={~p"/order/#{@shown_order.id}/receipt"}
                target="_blank"
                rel="noopener"
                variant="secondary"
              >
                {~t"View receipt"}
                <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              </.button>
              <.button
                :if={@next_delivery && @current_user}
                navigate={~p"/account"}
                variant="secondary"
                data-testid="manage-subscription"
              >
                {~t"Manage subscription"}
              </.button>
            </div>
            <.button
              :if={@placed? && @shown_order.fulfillment_method == :pickup}
              href={~p"/order/#{@shown_order.id}/pickup.ics"}
              variant="text"
              data-testid="add-to-calendar"
            >
              <.icon name="hero-calendar" class="size-4" />
              {~t"Add to calendar"}
            </.button>
            <.button navigate={~q"/#{language}/store"} variant="text">{~t"Back to the shop"}</.button>
          </div>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  # Only the order's owner subscribes, in mount.
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:placed:" <> _}, socket) do
    order = Orders.get_order_by_id!(socket.assigns.shown_order.id, authorize?: false)
    {:noreply, assign_order(socket, order)}
  end

  # Sent from the confirmation page rather than when the webhook places the
  # order, so the order keeps the visit's referrer and campaign.
  defp track_order_completed(socket, %{committed?: true} = order) do
    revenue = Analytics.revenue(order.grand_total)

    socket =
      Analytics.track(socket, "Order completed", Map.put(revenue, :subscription, order.subscription?),
        once: "order:#{order.id}"
      )

    if order.subscription?,
      do: Analytics.track(socket, "Subscription started", revenue, once: "subscription:#{order.id}"),
      else: socket
  end

  defp track_order_completed(socket, _order), do: socket

  # A guest is granted the order their browser's cart became: by guest_order_id once
  # `CheckoutCompleteController` released it, or by visitor_id when the webhook placed
  # it first. Everyone else goes through the order's read policy.
  def get_order(id, session, user) do
    load = [:receipt_available?, :committed?]

    case Orders.get_order_by_id(id, authorize?: false, load: load) do
      {:ok, order} ->
        if guest_order?(order, session), do: {:ok, order}, else: Orders.get_order_by_id(id, actor: user, load: load)

      error ->
        error
    end
  end

  defp owner?(order, session, user), do: guest_order?(order, session) or (user != nil and order.user_id == user.id)

  defp guest_order?(order, session) do
    order.id == session["guest_order_id"] or (order.visitor_id != nil and order.visitor_id == session["visitor_id"])
  end

  defp assign_order(socket, order) do
    {:ok, order} =
      Ash.load(
        order,
        [
          :customer_first_name,
          :line_items,
          :fulfillment_fee,
          :grand_total,
          :subscription?,
          :gift_voucher_sale?,
          :celebrated?,
          :voucher_card_ready_on,
          gift_voucher_line: :gift_voucher
        ],
        authorize?: false
      )

    subscription_line = Enum.find(order.line_items, & &1.interval_weeks)

    socket
    |> track_order_completed(order)
    |> assign(:page_title, ~t"Thank you for your order")
    |> assign(:shown_order, order)
    |> assign(:placed?, order.committed?)
    |> assign(:first_name, order.customer_first_name)
    |> assign(:date, Format.weekday_date(order.voucher_card_ready_on || order.fulfillment_date, Format.locale()))
    |> assign(:interval_weeks, subscription_line && subscription_line.interval_weeks)
    |> assign(:next_delivery, subscription_line && next_delivery(order, subscription_line))
    |> render_voucher_preview(order)
  end

  # The voucher is issued once the order is placed, so until then it shows a year from today.
  defp render_voucher_preview(%{assigns: %{voucher_preview: _}} = socket, _order), do: socket

  defp render_voucher_preview(socket, %{gift_voucher_sale?: true} = order) do
    socket
    |> assign(voucher_preview: nil, voucher_preview_error?: false)
    |> start_async(:voucher_preview, fn ->
      GiftVoucherPdf.preview(%{
        amount: order.grand_total,
        locale: order.voucher_locale,
        style: order.voucher_style,
        snow_seed: order.voucher_snow_seed,
        recipient_name: order.recipient_name,
        message: order.card_message || "",
        expires_on: order.gift_voucher_line.gift_voucher && order.gift_voucher_line.gift_voucher.expires_on
      })
    end)
  end

  defp render_voucher_preview(socket, _order), do: socket

  @impl true
  def handle_async(:voucher_preview, {:ok, {:ok, png}}, socket),
    do: {:noreply, assign(socket, voucher_preview: Base.encode64(png))}

  # The confirmation text already says the voucher is on its way, so it stands alone.
  def handle_async(:voucher_preview, result, socket) do
    Logger.warning("Order voucher preview failed: #{inspect(result)}")
    {:noreply, assign(socket, voucher_preview_error?: true)}
  end

  # Each later delivery is priced afresh, so this is today's price for it.
  defp next_delivery(order, line) do
    locale = Format.locale()

    date = Date.add(order.fulfillment_date, line.interval_weeks * 7)

    %{
      date: Format.weekday_date(date, locale),
      charge_date: Format.weekday_date(Edenflowers.Orders.Subscription.charged_on(date), locale),
      amount: Format.currency(Decimal.add(line.subtotal, order.fulfillment_fee || 0), locale)
    }
  end
end
