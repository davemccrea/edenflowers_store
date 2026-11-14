defmodule EdenflowersWeb.Admin.OverviewLive do
  @moduledoc """
  Back-office home page with a nine-day fulfillment calendar, items needing
  attention, sales, the monthly accounting report and the bank connection.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Bank
  alias Edenflowers.Courses
  alias Edenflowers.Events
  alias Edenflowers.Expenses
  alias Edenflowers.External.EnableBankingAPI
  alias Edenflowers.External.WeatherAPI
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Orders
  alias Edenflowers.Translations
  alias EdenflowersWeb.Admin.BankConnection
  alias EdenflowersWeb.Admin.OrderDetailComponents
  alias EdenflowersWeb.Admin.PubSub
  alias EdenflowersWeb.Admin.PushSubscriptions
  alias EdenflowersWeb.Admin.RouteDrawer
  alias EdenflowersWeb.Layouts

  @store_presence Events.topic(Events.store_presence())

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe([
        Events.admin_orders(),
        Events.admin_bookings(),
        Events.admin_subscriptions(),
        Events.shop_calendar_changed(),
        Events.admin_bank(),
        Events.admin_expenses(),
        Events.admin_report(socket.assigns.current_user.id)
      ])

      EdenflowersWeb.Presence.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, ~t"Overview")
     |> assign(:locale, Localize.get_locale())
     |> assign(:vapid_public_key, Edenflowers.WebPush.public_key())
     |> assign(:connected_customers, EdenflowersWeb.Presence.connected_customers())
     |> assign(route_date: nil, route_form: nil, route: nil, route_stale?: false)
     |> assign(:mapbox_token, Application.get_env(:edenflowers, :mapbox_token))
     |> refresh()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={greeting(@current_user, Edenflowers.ShopTime.now().hour)}>
          <:subtitle :if={@weather}><.weather weather={@weather} /></:subtitle>
          <:actions>
            <.button navigate={~p"/admin/orders/new"} variant="primary" size="sm" class="sm:order-last">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"New order"}
            </.button>
            <.button navigate={~p"/admin/orders/new-gift-voucher"} variant="secondary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" /> {~t"New voucher"}
            </.button>
          </:actions>
        </.admin_page_header>

        <.notifications_offer :if={@vapid_public_key} vapid_public_key={@vapid_public_key} />

        <.delivery_run run={@delivery_run} locale={@locale} />

        <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:grid-rows-[max-content_max-content_1fr] xl:items-start">
          <.attention_widget :if={@attention != []} groups={@attention} locale={@locale} />
          <%!-- Below xl the wrapper dissolves into the page grid, so a phone still reads
               sales before the monthly accounting. --%>
          <div class="contents xl:col-start-1 xl:row-span-3 xl:row-start-1 xl:block xl:min-w-0 xl:space-y-6">
            <.days_card
              days={@days}
              day={selected_day(@day, @days)}
              orders_by_date={@orders_by_date}
              calendar={@calendar}
              today={@today}
              locale={@locale}
            />
            <div class="grid min-w-0 gap-6 max-xl:order-last sm:grid-cols-2 sm:items-start">
              <.accounting_widget month={@report_month} bank_connection={@bank_connection} locale={@locale} />
              <.online_customers customers={@connected_customers} />
            </div>
          </div>
          <div class="min-w-0 xl:col-start-2">
            <.sales_widget
              sales={@sales}
              last_month={@last_month_sales}
              last_month_whole={@last_month_whole}
              last_month_to={@last_month_to}
              today={@today}
              owed={@owed}
              expenses={@expenses}
              locale={@locale}
            />
          </div>
        </div>
      </.admin_page>
      <RouteDrawer.route_drawer
        date={@route_date}
        orders={Map.get(@orders_by_date, @route_date, [])}
        form={@route_form}
        places={Fulfillment.route_places()}
        route={@route}
        route_stale?={@route_stale?}
        run={if @route_date == @today, do: run_left(@delivery_run), else: []}
        map_token={@mapbox_token}
        locale={@locale}
      />
    </Layouts.admin>
    """
  end

  # Only production can reach the bank, so elsewhere there's nothing to connect.
  defp bank_connection(actor) do
    if EnableBankingAPI.configured?() do
      {:ok, connection} =
        Bank.current_bank_connection(actor: actor, load: [:expired, :renewal_due, :balance, :reserved])

      {:configured, connection}
    else
      :not_configured
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    day =
      case Date.from_iso8601(params["day"] || "") do
        {:ok, date} -> date
        {:error, _} -> nil
      end

    {:noreply, assign(socket, :day, day)}
  end

  @impl true
  def handle_event("push_subscribed", params, socket),
    do: {:reply, PushSubscriptions.subscribe(params, socket.assigns.current_user), socket}

  def handle_event("mark_ready", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    result =
      with {:ok, order} <- Orders.get_order_by_id(id, actor: actor) do
        Orders.mark_order_ready(order, actor: actor)
      end

    case result do
      {:ok, _order} ->
        {:noreply,
         socket
         |> put_flash(:success, ~t"Order marked as ready.")
         |> push_event("order-ready", %{})}

      {:error, _error} ->
        {:noreply,
         socket
         |> refresh()
         |> put_flash(:error, ~t"The order has changed. Check its status and try again.")}
    end
  end

  def handle_event("connect_bank", _params, socket), do: BankConnection.connect(socket)

  def handle_event("open_route", %{"date" => date}, socket) do
    date = Date.from_iso8601!(date)
    orders = Map.get(socket.assigns.orders_by_date, date, [])
    run = if date == socket.assigns.today, do: run_left(socket.assigns.delivery_run), else: []

    {:noreply,
     socket
     |> assign(
       route_date: date,
       route_form: RouteDrawer.form(orders, date, run),
       route: nil,
       route_stale?: false
     )
     |> push_event("js-exec", %{to: "#route-drawer", attr: "phx-show"})}
  end

  def handle_event("close_route", _params, socket),
    do: {:noreply, assign(socket, route_date: nil, route_form: nil, route: nil, route_stale?: false)}

  # A changed form no longer matches the planned route: it stays to compare against, marked out of date.
  def handle_event("change_route", %{"route" => params}, socket),
    do: {:noreply, assign(socket, route_form: to_form(params, as: :route), route_stale?: socket.assigns.route != nil)}

  def handle_event("plan_route", %{"route" => params}, socket) do
    %{route_date: date, current_user: actor} = socket.assigns
    form = to_form(params, as: :route)

    # An input the browser let through, like a cleared time, shows as a route that couldn't be planned.
    route =
      case Fulfillment.plan_route(
             RouteDrawer.ticked(form),
             date,
             params["start"],
             params["finish"],
             params["departure"],
             actor: actor
           ) do
        {:ok, route} -> route
        {:error, _error} -> %{error: :invalid}
      end

    {:noreply, assign(socket, route_form: form, route: route, route_stale?: false)}
  end

  def handle_event("end_run", _params, socket) do
    case Orders.start_delivery_run(Edenflowers.ShopTime.today(), [], actor: socket.assigns.current_user) do
      :ok -> {:noreply, refresh(socket)}
      {:error, _error} -> {:noreply, put_flash(socket, :error, ~t"The delivery run couldn't be ended. Try again.")}
    end
  end

  def handle_event(
        "start_run",
        _params,
        %{assigns: %{route: %{stops: stops, back_at: back_at}, route_stale?: false}} = socket
      ) do
    %{route_date: date, current_user: actor} = socket.assigns

    case Orders.start_delivery_run(
           date,
           Enum.map(stops, & &1.order.id),
           %{planned_at: Enum.map(stops, & &1.starts_at), planned_back_at: back_at},
           actor: actor
         ) do
      # The run's own first stop: one planned first may have been handed over since.
      :ok ->
        case Orders.list_delivery_run!(date, actor: actor) do
          [first | _] -> {:noreply, push_navigate(socket, to: ~p"/admin/orders/#{first.id}")}
          [] -> {:noreply, refresh(socket)}
        end

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, ~t"The delivery run couldn't be started. Plan the route again.")}
    end
  end

  # A click that raced a form change: the route is out of date and the button is already gone.
  def handle_event("start_run", _params, socket), do: {:noreply, socket}

  # Only today, so a page left open overnight can't toggle yesterday.
  def handle_event("toggle-date", %{"date" => date}, socket) do
    date = Date.from_iso8601!(date)
    %{calendar: calendar, current_user: actor} = socket.assigns

    if date == Edenflowers.ShopTime.today() and Availability.today_toggle_state(calendar) do
      {:noreply, assign(socket, :calendar, Fulfillment.toggle_date!(calendar, date, actor: actor))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: @store_presence, event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :connected_customers, EdenflowersWeb.Presence.connected_customers())}
  end

  def handle_info(%Phoenix.Socket.Broadcast{}, socket),
    do: {:noreply, PubSub.schedule_refresh(socket, :overview)}

  def handle_info({:admin_refresh, :overview}, socket), do: {:noreply, refresh(socket)}

  def handle_info({:bank_statement_missing, month}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       ~t"The #{month} report was downloaded without the bank transactions, because the bank couldn't be read. Try again later, or reconnect the bank if it has disconnected."
     )}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # A forecast that can't be read leaves the weather out.
  @impl true
  def handle_async(:weather, {:ok, {:ok, weather}}, socket), do: {:noreply, assign(socket, :weather, weather)}
  def handle_async(:weather, _result, socket), do: {:noreply, assign(socket, :weather, nil)}

  # A day off the strip, such as yesterday's after midnight, falls back to today.
  defp selected_day(day, [today | _] = days), do: if(day in days, do: day, else: today)

  defp greeting(%{first_name: first_name}, hour) when is_binary(first_name) do
    cond do
      hour in 5..11 -> ~t"Good morning, #{first_name}"
      hour in 12..17 -> ~t"Good afternoon, #{first_name}"
      true -> ~t"Good evening, #{first_name}"
    end
  end

  defp greeting(_user, hour) do
    cond do
      hour in 5..11 -> ~t"Good morning"
      hour in 12..17 -> ~t"Good afternoon"
      true -> ~t"Good evening"
    end
  end

  defp refresh(socket) do
    actor = socket.assigns.current_user
    today = Edenflowers.ShopTime.today()

    {overdue, due} = Enum.split_with(Orders.list_orders_due_soon!(actor: actor), & &1.overdue?)

    {owed, to_refund} = actor |> balance_rows() |> Enum.split_with(&Decimal.positive?(&1.amount))
    payment_overdue = Enum.filter(owed, & &1.overdue?)

    attention =
      Enum.reject(
        [
          {"overdue-orders", "hero-clock", ~t"Overdue orders", Enum.map(overdue, &overdue_order_row/1)},
          {"failed-subscriptions", "hero-credit-card", ~t"Subscription payment failed",
           Enum.map(Orders.list_failed_subscriptions!(actor: actor), &subscription_row/1)},
          {"closed-day-subscriptions", "hero-calendar-days", ~t"Subscriptions on closed days",
           Enum.map(
             Orders.list_subscriptions_on_closed_days!(actor: actor),
             &closed_day_subscription_row(&1, socket.assigns.locale)
           )},
          {"refund", "hero-arrow-uturn-left", ~t"To refund", to_refund},
          {"payment-overdue", "hero-banknotes", ~t"Payment overdue", payment_overdue},
          {"missing-receipts", "hero-document-magnifying-glass", ~t"Bank payments without a receipt",
           Enum.map(Bank.bank_payments_missing_receipt!(actor: actor), &missing_receipt_row(&1, socket.assigns.locale))}
        ],
        fn {_key, _icon, _title, rows} -> rows == [] end
      )

    # Date.shift clamps to the month's last day, so 31.3. compares with 28.2.
    same_day_last_month = Date.shift(today, month: -1)

    socket
    |> fetch_weather()
    |> assign(:calendar, Fulfillment.get_shop_calendar!(actor: actor))
    |> assign(:bank_connection, bank_connection(actor))
    |> assign(:report_month, previous_month())
    |> assign(:days, Enum.to_list(Date.range(today, Date.add(today, 8))))
    |> assign(:orders_by_date, Enum.group_by(due, & &1.fulfillment_date))
    |> assign(:attention, attention)
    |> assign(:today, today)
    |> assign(:delivery_run, Orders.list_delivery_run!(today, actor: actor))
    |> assign(:owed, owed |> Enum.filter(&(&1.kind == :order)) |> sum_amounts())
    |> assign(:sales, Orders.sales_summary!(Date.beginning_of_month(today), today, actor: actor))
    |> assign(:expenses, Expenses.expenses_paid_totals!(Date.beginning_of_month(today), today, actor: actor))
    |> assign(:last_month_to, same_day_last_month)
    |> assign(
      :last_month_whole,
      Orders.sales_summary!(
        Date.beginning_of_month(same_day_last_month),
        Date.end_of_month(same_day_last_month),
        actor: actor
      )
    )
    |> assign(
      :last_month_sales,
      Orders.sales_summary!(Date.beginning_of_month(same_day_last_month), same_day_last_month, actor: actor)
    )
  end

  # A forecast already held shows at once. Otherwise it is read in the background,
  # with the weather on the page left as it is until the answer comes.
  defp fetch_weather(socket) do
    case WeatherAPI.cached() do
      nil ->
        socket = assign_new(socket, :weather, fn -> nil end)
        if connected?(socket), do: start_async(socket, :weather, &WeatherAPI.today/0), else: socket

      weather ->
        assign(socket, :weather, weather)
    end
  end

  # Largest first, either way.
  defp balance_rows(actor) do
    order_rows =
      for order <- Orders.list_unsettled_orders!(actor: actor) do
        %{
          id: "order-#{order.id}",
          who: order.customer_name || order.order_reference,
          what: if(order.customer_name, do: order.order_reference),
          kind: :order,
          amount: order.balance,
          overdue?: order.payment_overdue?,
          href: ~p"/admin/orders/#{order.id}"
        }
      end

    booking_rows =
      for registration <- Translations.translate_assoc(Courses.list_unsettled_registrations!(actor: actor), :course) do
        %{
          id: "booking-#{registration.id}",
          who: registration.name,
          what: registration.course.name,
          kind: :booking,
          amount: registration.balance,
          overdue?: registration.payment_overdue?,
          href:
            ~p"/admin/courses/#{registration.course_id}?#{[booking: registration.id]}" <>
              "#registration-#{registration.id}"
        }
      end

    Enum.sort_by(order_rows ++ booking_rows, &Decimal.abs(&1.amount), {:desc, Decimal})
  end

  defp missing_receipt_row(payment, locale) do
    %{
      id: payment.id,
      who: payment.counterparty || ~t"Unknown payee",
      what: Format.date(payment.booked_on, locale),
      amount: payment.amount,
      href: ~p"/admin/expenses?#{[payment: payment.id]}" <> "#bank-payment-#{payment.id}"
    }
  end

  defp order_row_link(order) do
    %{
      id: "order-#{order.id}",
      who: order.customer_name || ~t"Unnamed customer",
      what: Format.weekday_day_month(order.fulfillment_date, Format.locale()),
      href: ~p"/admin/orders/#{order.id}"
    }
  end

  defp overdue_order_row(order) do
    row = order_row_link(order)
    %{row | what: "#{row.what} · #{fulfillment_method_label(order.fulfillment_method)}"}
  end

  defp subscription_row(subscription) do
    %{
      id: "subscription-#{subscription.id}",
      who: subscription.user.name || ~t"Unnamed customer",
      what: Translations.translate(subscription.product_variant.product).name,
      href: ~p"/admin/subscriptions/#{subscription.id}"
    }
  end

  # The calendar doesn't move these: Jennie delivers anyway or moves the order once it's booked.
  defp closed_day_subscription_row(subscription, locale) do
    row = subscription_row(subscription)
    dates = Enum.map_join(subscription.closed_delivery_dates, ", ", &Format.weekday_day_month(&1, locale))
    %{row | what: "#{row.what} · #{dates}"}
  end

  attr :vapid_public_key, :string, required: true

  # Starts hidden: the PushNudge hook shows it only in the installed app, before
  # it has asked for notification permission.
  defp notifications_offer(assigns) do
    ~H"""
    <section
      id="notifications-offer"
      phx-hook=".PushNudge"
      phx-update="ignore"
      hidden
      data-vapid-public-key={@vapid_public_key}
      aria-labelledby="notifications-offer-title"
      class="admin-card mb-6 flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5"
    >
      <div class="flex items-start gap-3">
        <.icon name="hero-bell" class="text-primary mt-0.5 h-5 w-5 shrink-0" />
        <div>
          <h2 id="notifications-offer-title" class="text-base-content text-base font-semibold">
            {~t"Get new orders on this phone"}
          </h2>
          <p class="text-base-content/75 text-sm">{~t"Same-day orders arrive straight away."}</p>
        </div>
      </div>
      <div class="flex justify-end gap-2">
        <.button type="button" variant="ghost" size="sm" data-push-nudge="dismiss">{~t"Not now"}</.button>
        <.button type="button" variant="primary" size="sm" data-push-nudge="enable">{~t"Turn on"}</.button>
      </div>
    </section>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PushNudge">
      import { pushSupported, resyncSubscription, subscribeDevice } from "@/js/push";

      /**
       * The Overview card offering order notifications, shown once in the installed
       * app before it has asked for permission. Either button hides it for good on
       * this device; the account page's switch is there after that.
       */
      const PUSH_NUDGE_DISMISSED_KEY = "eden:push-nudge-dismissed";

      export default {
        mounted() {
          // The Overview is where the installed app opens, so every launch re-saves
          // this device's subscription.
          if (pushSupported()) resyncSubscription(this);

          const installed =
            window.matchMedia("(display-mode: standalone)").matches ||
            /** @type {any} */ (navigator).standalone === true;

          if (
            !installed ||
            !pushSupported() ||
            Notification.permission !== "default" ||
            this.dismissed()
          )
            return;

          this.js().removeAttribute(this.el, "hidden");

          this.el
            .querySelector("[data-push-nudge=dismiss]")
            ?.addEventListener("click", () => this.dismiss());

          this.el
            .querySelector("[data-push-nudge=enable]")
            ?.addEventListener("click", () => {
              subscribeDevice(this, this.el.dataset.vapidPublicKey);
              this.dismiss();
            });
        },

        dismissed() {
          try {
            return localStorage.getItem(PUSH_NUDGE_DISMISSED_KEY) !== null;
          } catch {
            return false;
          }
        },

        dismiss() {
          try {
            localStorage.setItem(PUSH_NUDGE_DISMISSED_KEY, "1");
          } catch {
            // Without storage the card simply comes back next time.
          }
          this.js().setAttribute(this.el, "hidden", "");
        },
      };
    </script>
    """
  end

  attr :sales, :map, required: true, doc: "this month to today, from `sales_summary`"
  attr :last_month, :map, required: true, doc: "last month to `last_month_to`"
  attr :last_month_whole, :map, required: true, doc: "all of last month, for the chart"
  attr :last_month_to, Date, required: true
  attr :today, Date, required: true
  attr :owed, :any, required: true, doc: "what placed orders still owe, overdue or not"
  attr :expenses, :list, required: true, doc: "this month's paid expenses to today, from `paid_totals`"
  attr :locale, :any, required: true

  defp sales_widget(assigns) do
    assigns =
      assign(assigns, :chart, pace_chart(assigns.sales.revenue_by_day, assigns.last_month_whole.revenue_by_day))

    ~H"""
    <.widget title={~t"This month"}>
      <div class="grid-cols-[minmax(0,1fr)_auto] grid items-start gap-x-6">
        <dl id="revenue" class="min-w-0">
          <dt class="text-base-content/75 text-sm">{~t"Revenue"}</dt>
          <dd class="text-base-content text-3xl font-semibold tabular-nums tracking-tight">
            {Format.currency(@sales.revenue, @locale)}
          </dd>
        </dl>

        <dl id="sales" class="text-right">
          <dt class="text-base-content/75 text-sm">{~t"Sales"}</dt>
          <dd class="text-base-content text-xl font-semibold tabular-nums">{@sales.order_count}</dd>
        </dl>
      </div>

      <%!-- The date once, then each figure under the one it compares with. --%>
      <dl id="last-month" class="text-base-content/75 mt-3 text-sm">
        <dt class="text-xs">{~t"Last month by #{date = Format.day_month(@last_month_to, @locale)}"}</dt>
        <dd class="flex justify-between gap-4 tabular-nums">
          <span id="revenue-last-month">{Format.currency(@last_month.revenue, @locale)}</span>
          <span id="sales-last-month">{@last_month.order_count}</span>
        </dd>
      </dl>

      <figure id="revenue-pace" class="mt-4" aria-hidden="true">
        <div class="border-base-content/12 relative h-28 border-b">
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" class="absolute inset-0 h-full w-full overflow-visible">
            <defs>
              <linearGradient id="revenue-pace-fill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" class="[stop-color:var(--color-primary)] [stop-opacity:0.35]" />
                <stop offset="1" class="[stop-color:var(--color-primary)] [stop-opacity:0.02]" />
              </linearGradient>
            </defs>
            <path d={@chart.this_area} fill="url(#revenue-pace-fill)" />
            <path
              d={@chart.last_line}
              fill="none"
              stroke-dasharray="3 3"
              vector-effect="non-scaling-stroke"
              class="stroke-base-content/35 stroke-[1.5]"
            />
            <path
              d={@chart.this_line}
              fill="none"
              stroke-linejoin="round"
              vector-effect="non-scaling-stroke"
              class="stroke-primary stroke-2"
            />
          </svg>
          <%!-- Where last month stood on the same day: the figure in the row above. --%>
          <span
            class="border-base-content/50 bg-base-100 absolute h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full border-2"
            style={"left: #{@chart.last_today_x}%; top: #{@chart.last_today_y}%"}
          />
          <span
            class="absolute h-2.5 w-2.5 -translate-x-1/2 -translate-y-1/2"
            style={"left: #{@chart.today_x}%; top: #{@chart.today_y}%"}
          >
            <span class="bg-primary/40 absolute inset-0 rounded-full motion-safe:animate-ping" />
            <span class="bg-primary ring-base-100 absolute inset-0 rounded-full ring-2" />
          </span>
        </div>
        <div class="text-base-content/75 mt-1 flex justify-between text-xs tabular-nums">
          <span>{Format.day_month(Date.beginning_of_month(@today), @locale)}</span>
          <span>{Format.day_month(Date.end_of_month(@today), @locale)}</span>
        </div>
        <figcaption class="text-base-content/75 mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs">
          <span class="flex items-center gap-1.5">
            <span class="bg-primary h-0.5 w-4 rounded-full" /> {~t"This month"}
          </span>
          <span class="flex items-center gap-1.5">
            <span class="border-base-content/35 border-t-[1.5px] w-4 border-dashed" />
            {~t"Last month"}
            <span class="text-base-content/85 tabular-nums">{Format.currency(@last_month_whole.revenue, @locale)}</span>
          </span>
        </figcaption>
      </figure>

      <p
        :if={Decimal.positive?(@owed)}
        id="still-owed"
        class="border-base-content/12 text-base-content/75 mt-4 flex items-baseline justify-between gap-4 border-t pt-3 text-sm"
      >
        {~t"Still to come in"}
        <span class="text-base-content font-semibold tabular-nums">{Format.currency(@owed, @locale)}</span>
      </p>

      <p
        :if={@expenses != []}
        id="expenses-paid"
        class="border-base-content/12 text-base-content/75 mt-4 flex items-baseline justify-between gap-4 border-t pt-3 text-sm"
      >
        {~t"Expenses paid"}
        <span class="text-base-content text-right font-semibold tabular-nums">
          <span :for={%{currency: currency, total: total} <- @expenses} class="block">
            {Format.currency_in(total, currency, @locale)}
          </span>
        </span>
      </p>
    </.widget>
    """
  end

  # Running revenue totals by day of month, in a 100×100 box with the y-axis
  # flipped, so this month reads against where last month stood on the same day.
  defp pace_chart(this_month, last_month) do
    this = running_totals(this_month)
    last = running_totals(last_month)
    span = max(Date.days_in_month(hd(this_month).date), length(last_month))
    values = this ++ last
    low = min(0, Enum.min(values))
    high = max(Enum.max(values), low + 1)

    point = fn index, value ->
      {Float.round(index / (span - 1) * 100, 2), Float.round(96 - (value - low) / (high - low) * 92, 2)}
    end

    this_points = this |> Enum.with_index() |> Enum.map(fn {value, index} -> point.(index, value) end)
    last_points = last |> Enum.with_index() |> Enum.map(fn {value, index} -> point.(index, value) end)
    {today_x, today_y} = List.last(this_points)
    # Date.shift clamps the same day last month, so 31.3. compares with 28.2., the line's end.
    {last_today_x, last_today_y} = Enum.at(last_points, min(length(this), length(last)) - 1)
    {_, baseline} = point.(0, low)

    %{
      this_line: svg_path(this_points),
      this_area: svg_path(this_points) <> " L#{today_x},#{baseline} L0,#{baseline} Z",
      last_line: svg_path(last_points),
      today_x: today_x,
      today_y: today_y,
      last_today_x: last_today_x,
      last_today_y: last_today_y
    }
  end

  defp running_totals(days) do
    days
    |> Enum.scan(Decimal.new(0), &Decimal.add(&1.revenue, &2))
    |> Enum.map(&Decimal.to_float/1)
  end

  defp svg_path([{x, y} | rest]), do: Enum.reduce(rest, "M#{x},#{y}", fn {x, y}, path -> path <> " L#{x},#{y}" end)

  attr :customers, :list, required: true

  defp online_customers(assigns) do
    {named, anonymous} = Enum.split_with(assigns.customers, & &1.user_id)
    assigns = assign(assigns, named: named, anonymous_count: length(anonymous))

    ~H"""
    <div id="connected-customers" class="min-w-0">
      <.widget title={~t"Online customers"}>
        <p class="text-2xl font-semibold tabular-nums" id="connected-customers-count">
          {length(@customers)}
        </p>
        <p :if={@customers == []} class="text-base-content/75 mt-2 text-sm">
          {~t"No customers online"}
        </p>
        <p :if={@anonymous_count > 0} id="anonymous-visitors-count" class="text-base-content/75 mt-2 text-sm">
          {dngettext("admin", "%{count} anonymous visitor", "%{count} anonymous visitors", @anonymous_count)}
        </p>
        <ul :if={@named != []} id="online-customers-list" class="mt-2 max-h-60 space-y-2 overflow-y-auto text-sm">
          <li :for={customer <- @named} id={"connected-#{customer.key}"}>
            <.link navigate={~p"/admin/customers/#{customer.user_id}"} class="break-words hover:underline">
              {customer.name}
            </.link>
          </li>
        </ul>
      </.widget>
    </div>
    """
  end

  # A plain GET, not a LiveView event, so the browser downloads the zip itself. The
  # new tab loads while the zip builds and closes once the download starts; on an
  # error it shows Overview with the flash.
  attr :month, :string, required: true
  attr :bank_connection, :any, required: true, doc: "`:not_configured` or `{:configured, connection or nil}`"
  attr :locale, :any, required: true

  defp accounting_widget(assigns) do
    ~H"""
    <.widget title={~t"Accounting"}>
      <h3 class="text-base-content mb-2 text-sm font-semibold">{~t"Accountant report"}</h3>
      <form
        id="report-form"
        action={~p"/admin/reports"}
        method="get"
        target="_blank"
        class="flex flex-wrap items-end gap-3"
      >
        <label class="min-w-40 flex flex-1 flex-col gap-1 text-sm">
          {~t"Month"}
          <input type="month" name="month" value={@month} required class="input w-full" />
        </label>
        <.button type="submit" variant="secondary">
          <.icon name="hero-arrow-down-tray" class="h-4 w-4" />
          {~t"Download"}
        </.button>
      </form>
      <.bank_status
        :if={@bank_connection != :not_configured}
        connection={elem(@bank_connection, 1)}
        locale={@locale}
      />
    </.widget>
    """
  end

  attr :connection, :any, required: true
  attr :locale, :any, required: true

  # The bank marks expenses and invoices paid from its payments.
  defp bank_status(assigns) do
    ~H"""
    <div id="bank-status" role="status" class="border-base-content/12 mt-5 border-t pt-4 text-sm">
      <h3 class="text-base-content mb-2 flex flex-wrap items-center gap-2 font-semibold">
        {~t"Bank"}
        <%= cond do %>
          <% is_nil(@connection) -> %>
            <.badge tone={:neutral}>{~t"Not connected"}</.badge>
          <% @connection.expired -> %>
            <.badge tone={:error}>{~t"Disconnected"}</.badge>
          <% @connection.renewal_due -> %>
            <.badge tone={:warning}>{~t"Ending soon"}</.badge>
          <% true -> %>
            <.badge tone={:success}>{~t"Connected"}</.badge>
        <% end %>
      </h3>
      <dl :if={@connection && @connection.balance} id="bank-balance" class="[&:not(:last-child)]:mb-3">
        <dt class="text-base-content/75">
          {if @connection.available_balance, do: ~t"Available", else: ~t"Balance"}
        </dt>
        <dd class="text-base-content text-2xl font-semibold tabular-nums tracking-tight">
          {Format.currency(@connection.balance, @locale)}
        </dd>
        <dd class="text-base-content/75 text-xs">
          <span :if={@connection.reserved} id="bank-balance-booked" class="tabular-nums">
            {~t"Booked #{amount = Format.currency(@connection.booked_balance, @locale)}"} ·
          </span>
          {balance_read(@connection.balance_read_at, @locale)}
        </dd>
      </dl>
      <p
        :if={is_nil(@connection) or @connection.expired or @connection.renewal_due}
        class="text-base-content/75 [&:not(:last-child)]:mb-3"
      >
        <%= cond do %>
          <% is_nil(@connection) -> %>
            {~t"Connect it to mark expenses and invoices paid as payments leave or arrive."}
          <% @connection.expired -> %>
            {~t"The connection ended on #{date = Format.date(@connection.valid_until, @locale)}. Connect again to keep payments up to date."}
          <% true -> %>
            {~t"It ends on #{date = Format.date(@connection.valid_until, @locale)}. Connect again to keep payments up to date."}
        <% end %>
      </p>
      <.button
        :if={is_nil(@connection) or @connection.renewal_due}
        phx-click="connect_bank"
        variant="secondary"
        size="sm"
      >
        <.icon name="hero-building-library" class="h-4 w-4" />
        {if @connection, do: ~t"Reconnect", else: ~t"Connect bank"}
      </.button>
    </div>
    """
  end

  # Read four times a day, so a date instead of "today" tells Jennie the figure is old.
  defp balance_read(read_at, locale) do
    read_at = DateTime.shift_zone!(read_at, Edenflowers.ShopTime.timezone())

    if DateTime.to_date(read_at) == Edenflowers.ShopTime.today() do
      ~t"Updated today at #{time = Format.time(DateTime.to_time(read_at), locale)}"
    else
      ~t"Updated #{time = Format.datetime(read_at, locale)}"
    end
  end

  defp previous_month do
    Edenflowers.ShopTime.today()
    |> Date.beginning_of_month()
    |> Date.add(-1)
    |> Date.to_iso8601()
    |> String.slice(0, 7)
  end

  # The stops still to deliver; handed-over ones stay in the run only to count progress.
  defp run_left(run), do: Enum.filter(run, & &1.fulfillable?)

  attr :run, :list, required: true, doc: "today's `Orders.list_delivery_run`"
  attr :locale, :any, required: true

  # Shown while stops are left; the order pages say when the last one is delivered.
  defp delivery_run(assigns) do
    ~H"""
    <OrderDetailComponents.run_bar :if={run_left(@run) != []} id="delivery-run" run={@run} locale={@locale}>
      <:actions>
        <.button
          id="end-delivery-run"
          type="button"
          variant="ghost"
          size="sm"
          phx-click="end_run"
          data-confirm={~t"End the delivery run? Its orders stay as they are, still due today."}
        >
          {~t"End run"}
        </.button>
      </:actions>
    </OrderDetailComponents.run_bar>
    """
  end

  attr :groups, :list, required: true, doc: "`{key, icon, title, rows}`, each with at least one row"
  attr :locale, :any, required: true

  # Collapsed to a line per kind of problem, so it stays short on a phone.
  defp attention_widget(assigns) do
    ~H"""
    <section
      id="attention"
      aria-labelledby="attention-title"
      class="admin-card shadow-[inset_4px_0_0_var(--color-warning)] min-w-0 p-4 sm:p-5 xl:col-start-2"
    >
      <h2 id="attention-title" class="text-base-content mb-2 text-base font-semibold">
        {~t"Needs attention"}
      </h2>
      <ul class="divide-base-content/12 divide-y text-sm">
        <li :for={{key, icon, title, rows} <- @groups}>
          <details id={"attention-#{key}"} phx-mounted={JS.ignore_attributes(["open"])} class="group">
            <summary class="touch-target flex cursor-pointer list-none items-center gap-3 py-2">
              <.icon name={icon} class="text-base-content/60 h-4 w-4 shrink-0" />
              <%!-- Inline, so a title that wraps keeps its count beside the last word. --%>
              <span class="text-base-content min-w-0 flex-1">
                {title}
                <span class="ml-1.5 inline-block align-middle">
                  <.count_badge count={length(rows)} active={true} tone={:warning} />
                </span>
              </span>
              <span :if={Map.has_key?(hd(rows), :amount)} class="text-base-content shrink-0 tabular-nums">
                {Format.currency(sum_amounts(rows), @locale)}
              </span>
              <.icon
                name="hero-chevron-down"
                class="text-base-content/60 h-4 w-4 shrink-0 transition-transform group-open:rotate-180"
              />
            </summary>
            <ul class="border-base-content/12 divide-base-content/12 mb-2 ml-2 divide-y border-l pl-5">
              <.link_row :for={row <- rows} id={"attention-#{key}-#{row.id}"} row={row} locale={@locale} />
            </ul>
          </details>
        </li>
      </ul>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :row, :map, required: true, doc: "`who`, `what` (or nil), `href`, and an optional `amount`"
  attr :locale, :any, required: true

  defp link_row(assigns) do
    ~H"""
    <li id={@id}>
      <.link
        navigate={@row.href}
        class="-mx-2 flex items-baseline justify-between gap-4 px-2 py-2 transition-colors hover:bg-base-content/5"
      >
        <span class="min-w-0">
          <span class="text-base-content block truncate font-semibold">{@row.who}</span>
          <span :if={@row.what} class="text-base-content/75 block truncate text-sm">{@row.what}</span>
        </span>
        <span :if={@row[:amount]} class="text-base-content shrink-0 tabular-nums">
          {Format.currency(Decimal.abs(@row.amount), @locale)}
        </span>
      </.link>
    </li>
    """
  end

  defp sum_amounts(rows), do: rows |> Enum.map(&Decimal.abs(&1.amount)) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

  attr :id, :string, required: true
  attr :texts, :any, required: true, doc: "`{label, empty}` from `day_texts/2`"
  attr :date, Date, required: true
  attr :orders, :list, required: true
  attr :booking, :atom, required: true, doc: "`:open`, `:closed` or nil, see `booking/2`"
  attr :locale, :any, required: true
  attr :class, :any, default: nil

  defp day_section(assigns) do
    {label, empty} = assigns.texts
    assigns = assign(assigns, label: label, empty: empty, groups: by_method(assigns.orders))

    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"} class={@class}>
      <h3 id={"#{@id}-title"} class="sr-only">
        {@label} {Format.weekday_day_month(@date, @locale)}
      </h3>

      <div class="space-y-4">
        <div
          :for={{{method, orders}, index} <- Enum.with_index(@groups)}
          id={"#{@id}-#{method}"}
          class={index > 0 && "pt-4"}
        >
          <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 pb-2">
            <h4 class="eyebrow text-base-content/75 flex items-center gap-1.5">
              <.icon name={fulfillment_method_icon(method)} class="text-base-content/50 h-4 w-4 shrink-0" />
              {method_heading(method)}
              <.count_badge count={length(orders)} active={true} />
            </h4>
            <span class="text-base-content/75 text-sm tabular-nums">
              {~t"#{ready = Enum.count(orders, & &1.can_undo_ready?)} of #{total = length(orders)} ready"}
            </span>
            <.button
              :if={method == :delivery}
              id={"#{@id}-route"}
              type="button"
              variant="ghost"
              size="sm"
              phx-click="open_route"
              phx-value-date={Date.to_iso8601(@date)}
            >
              <.icon name="hero-map" class="h-4 w-4" /> {~t"Plan route"}
            </.button>
            <.day_booking_controls :if={index == 0} id={@id} date={@date} booking={@booking} />
          </div>
          <ul class="divide-base-content/12 -mx-4 divide-y sm:-mx-5">
            <.order_row :for={order <- orders} order={order} />
          </ul>
        </div>
      </div>

      <div :if={@orders == []} class="flex flex-wrap items-center justify-between gap-3 py-5">
        <p class="text-base-content/75 flex items-center gap-2 text-sm">
          <.icon name="hero-check-circle" class="h-5 w-5 shrink-0" />
          {@empty}
        </p>
        <.day_booking_controls id={@id} date={@date} booking={@booking} />
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :date, Date, required: true
  attr :booking, :atom, required: true

  defp day_booking_controls(assigns) do
    ~H"""
    <div :if={@booking} class="ml-auto flex flex-wrap items-center justify-end gap-2">
      <.badge :if={@booking == :closed} id={"#{@id}-closed"} tone={:warning}>{~t"Closed"}</.badge>
      <.button
        id={"#{@id}-toggle"}
        type="button"
        variant="ghost"
        size="sm"
        aria-describedby={"#{@id}-title"}
        phx-click="toggle-date"
        phx-value-date={Date.to_iso8601(@date)}
        data-confirm={@booking == :open && ~t"Stop orders for this day? Customers can't order for it until you reopen it."}
      >
        <%= if @booking == :open do %>
          <.icon name="hero-no-symbol" class="h-4 w-4" /> {~t"Stop orders"}
        <% else %>
          <.icon name="hero-arrow-path" class="h-4 w-4" /> {~t"Reopen orders"}
        <% end %>
      </.button>
    </div>
    """
  end

  attr :days, :list, required: true, doc: "today and the 8 days after it"
  attr :day, Date, required: true, doc: "the day whose orders are listed"
  attr :orders_by_date, :map, required: true
  attr :calendar, :map, required: true
  attr :today, Date, required: true
  attr :locale, :any, required: true

  # Nine days because Jennie buys from the wholesaler anywhere from a day to a week ahead.
  defp days_card(assigns) do
    ~H"""
    <section id="overview-orders" aria-labelledby="overview-orders-title" class="admin-card p-4 sm:p-5">
      <div class="mb-4 flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
        <h2 id="overview-orders-title" class="text-base-content text-base font-semibold">{~t"Orders"}</h2>
        <.link
          navigate={~p"/admin/orders"}
          class="text-primary touch-target inline-flex items-center py-1 text-sm hover:underline"
        >
          {~t"View all orders"} →
        </.link>
      </div>
      <%!-- Scrolls sideways on a phone, bleeding to the card's edges. --%>
      <ol
        id="days"
        phx-hook=".ScrollToCurrent"
        aria-label={~t"Days"}
        class="admin-scroll-fade [scrollbar-width:none] relative -mx-4 flex snap-x scroll-px-4 gap-1 overflow-x-auto px-4 sm:mx-0 sm:grid sm:grid-cols-9 sm:overflow-visible sm:px-0"
      >
        <li :for={date <- @days} id={"day-#{date}"} class="w-13 shrink-0 snap-start sm:w-auto">
          <.day_cell
            date={date}
            count={length(Map.get(@orders_by_date, date, []))}
            closed?={Availability.customer_cell_state(@calendar, date) == :closed}
            selected?={date == @day}
            today?={date == @today}
            locale={@locale}
          />
        </li>
      </ol>

      <.day_section
        id="day-orders"
        texts={day_texts(@day, @today)}
        date={@day}
        orders={Map.get(@orders_by_date, @day, [])}
        booking={if @day == @today, do: Availability.today_toggle_state(@calendar)}
        locale={@locale}
        class="mt-4 pt-4"
      />
    </section>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToCurrent">
      /**
       * Scrolls a sideways list so its `aria-current` item is in view, such as the
       * Overview's day strip opened on a day further out. Only on mount: a tapped
       * item is already in view.
       */
      export default {
        mounted() {
          const current = this.el.querySelector("[aria-current]")?.closest("li");
          if (!(current instanceof HTMLElement)) return;

          // scrollLeft rather than scrollIntoView, which can also scroll the page.
          this.el.scrollLeft =
            current.offsetLeft - (this.el.clientWidth - current.offsetWidth) / 2;
        },
      };
    </script>
    """
  end

  attr :weather, :map, required: true

  defp weather(assigns) do
    gettext_comment("Today's highest temperature, before e.g. \"3°\" in the Overview's weather.")
    high = ~t"High"
    gettext_comment("Today's lowest temperature, before e.g. \"-1°\" in the Overview's weather.")
    low = ~t"Low"
    assigns = assign(assigns, label: weather_condition(assigns.weather.condition), high: high, low: low)

    ~H"""
    <span id="today-weather" class="flex items-center gap-1.5 tabular-nums">
      <svg
        role="img"
        aria-label={@label}
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.75"
        stroke-linecap="round"
        stroke-linejoin="round"
        class="text-base-content/60 size-5"
      >
        <title>{@label}</title>
        <path :for={d <- weather_icon(@weather.condition, @weather.night?)} d={d} />
      </svg>
      <span class="text-base-content/60 text-sm">{@high}</span>
      <span class="text-base-content text-sm">{@weather.high}°</span>
      <span class="text-base-content/60 ml-1 text-sm">{@low}</span>
      <span class="text-base-content text-sm">{@weather.low}°</span>
    </span>
    """
  end

  # Lucide's weather icons (ISC licence, lucide.dev), as their paths.
  @cloud "M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"

  defp weather_icon(:thunder, _night?),
    do: ["M6 16.326A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 .5 8.973", "m13 12-3 5h4l-3 5"]

  defp weather_icon(:sleet, _night?),
    do: [@cloud, "M16 14v2", "M8 14v2", "M16 20h.01", "M8 20h.01", "M12 16v2", "M12 22h.01"]

  defp weather_icon(:snow, _night?),
    do: [@cloud, "M8 15h.01", "M8 19h.01", "M12 17h.01", "M12 21h.01", "M16 15h.01", "M16 19h.01"]

  defp weather_icon(:rain, _night?), do: [@cloud, "M16 14v6", "M8 14v6", "M12 16v6"]
  defp weather_icon(:fog, _night?), do: [@cloud, "M16 17H7", "M17 21H9"]

  defp weather_icon(:partly_cloudy, true),
    do: [
      "M13 16a3 3 0 0 1 0 6H7a5 5 0 1 1 4.9-6z",
      "M18.376 14.512a6 6 0 0 0 3.461-4.127c.148-.625-.659-.97-1.248-.714a4 4 0 0 1-5.259-5.26c.255-.589-.09-1.395-.716-1.248a6 6 0 0 0-4.594 5.36"
    ]

  defp weather_icon(:partly_cloudy, false),
    do: [
      "M12 2v2",
      "m4.93 4.93 1.41 1.41",
      "M20 12h2",
      "m19.07 4.93-1.41 1.41",
      "M15.947 12.65a4 4 0 0 0-5.925-4.128",
      "M13 22H7a5 5 0 1 1 4.9-6H13a3 3 0 0 1 0 6Z"
    ]

  defp weather_icon(:cloudy, _night?), do: ["M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"]

  defp weather_icon(:clear, true),
    do: [
      "M20.985 12.486a9 9 0 1 1-9.473-9.472c.405-.022.617.46.402.803a6 6 0 0 0 8.268 8.268c.344-.215.825-.004.803.401"
    ]

  defp weather_icon(:clear, false),
    do: [
      "M16 12a4 4 0 1 1-8 0a4 4 0 1 1 8 0",
      "M12 2v2",
      "M12 20v2",
      "m4.93 4.93 1.41 1.41",
      "m17.66 17.66 1.41 1.41",
      "M2 12h2",
      "M20 12h2",
      "m6.34 17.66-1.41 1.41",
      "m19.07 4.93-1.41 1.41"
    ]

  defp weather_condition(:thunder), do: ~t"Thunder"
  defp weather_condition(:sleet), do: ~t"Sleet"
  defp weather_condition(:snow), do: ~t"Snow"
  defp weather_condition(:rain), do: ~t"Rain"
  defp weather_condition(:fog), do: ~t"Fog"
  defp weather_condition(:partly_cloudy), do: ~t"Partly cloudy"
  defp weather_condition(:cloudy), do: ~t"Cloudy"
  defp weather_condition(:clear), do: ~t"Clear"

  attr :date, Date, required: true
  attr :count, :integer, required: true
  attr :closed?, :boolean, required: true
  attr :selected?, :boolean, required: true
  attr :today?, :boolean, required: true
  attr :locale, :any, required: true

  # The count sits in a badge so it can't be read as part of the date. A closed day
  # is muted but still shows its orders, such as a custom order taken anyway.
  defp day_cell(assigns) do
    ~H"""
    <.link
      patch={if @today?, do: ~p"/admin", else: ~p"/admin?#{[day: Date.to_iso8601(@date)]}"}
      aria-current={@selected? && "true"}
      aria-label={day_cell_label(@date, @count, @closed?, @locale)}
      class={["flex flex-col items-center gap-0.5 border py-2 transition-colors", day_cell_class(@selected?, @closed?)]}
    >
      <span class={["text-xs", !@selected? && !@closed? && "text-base-content/75"]}>
        {Localize.Date.to_string!(@date, locale: @locale, format: "ccc")}
      </span>
      <span class="text-sm font-semibold tabular-nums">
        {@date.day}
      </span>
      <span class="flex h-5 items-center">
        <span
          :if={@count > 0}
          class="badge badge-sm bg-primary/10 text-primary rounded-full border-0 font-semibold tabular-nums"
        >
          {@count}
        </span>
        <.icon :if={@count == 0 and @closed?} name="hero-no-symbol" class="h-4 w-4" />
      </span>
    </.link>
    """
  end

  defp day_cell_class(true = _selected?, _closed?), do: "border-primary bg-primary/5 text-base-content"
  defp day_cell_class(false, true), do: "border-transparent bg-base-200/70 text-base-content/60 hover:bg-base-200"
  defp day_cell_class(false, false), do: "border-transparent hover:bg-base-200/60"

  defp day_cell_label(date, count, closed?, locale) do
    [
      Format.weekday_day_month(date, locale),
      closed? && ~t"Closed",
      count > 0 && ~t"#{count = count} order(s)"N
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  # Return the relative heading and empty-state text. Dates after tomorrow have
  # no relative heading; the caller displays the date instead.
  defp day_texts(date, today) do
    case Date.diff(date, today) do
      0 -> {~t"Today", ~t"Nothing to make today"}
      1 -> {~t"Tomorrow", ~t"Nothing to make tomorrow"}
      _ -> {nil, ~t"Nothing to make"}
    end
  end

  attr :order, :map, required: true

  # What the florist needs to act on, in reading order: whose order, what to make,
  # whether there's a card to write, and when it leaves the shop. Price lives on the
  # order page; it doesn't change what gets made.
  defp order_row(assigns) do
    assigns = assign(assigns, :items, Enum.reject(assigns.order.line_items, & &1.is_card))

    ~H"""
    <li
      id={"day-order-#{@order.id}"}
      class="transition-colors focus-within:bg-base-200/60 hover:bg-base-200/60"
    >
      <.link
        navigate={~p"/admin/orders/#{@order.id}"}
        class="block px-4 pt-4 pb-2 focus-visible:-outline-offset-2 sm:px-5"
      >
        <div class="grid-cols-[minmax(0,1fr)_auto] grid items-baseline gap-x-3 gap-y-1">
          <span class="text-base-content min-w-0 break-words font-semibold">
            {@order.customer_name || ~t"Unnamed customer"}
          </span>
          <span
            :if={Format.fulfillment_time_range(@order, Format.locale())}
            class="text-base-content col-start-2 row-start-1 flex items-center justify-end gap-1 whitespace-nowrap text-xs tabular-nums sm:text-sm"
            data-testid="fulfillment-time"
          >
            <.icon name="hero-clock" class="text-base-content/50 h-3.5 w-3.5" />
            {Format.fulfillment_time_range(@order, Format.locale())}
          </span>

          <ul :if={@items != []} class="text-base-content col-start-1 row-start-2 min-w-0 space-y-0.5 text-sm">
            <li :for={item <- @items} class="break-words" phx-no-format>
              <span class="tabular-nums">{item.quantity} ×</span>
              <span>{item.product_name}</span><span :if={item.variant_size || item.bow_colour} class="text-base-content/75">, {Format.line_item_choices(item)}</span>
            </li>
          </ul>
          <span
            :if={@order.distance_km}
            class="text-base-content/75 col-start-2 row-start-2 text-right text-xs tabular-nums"
          >
            {@order.distance_km} km
          </span>
        </div>

        <p
          :if={present?(@order.florist_note)}
          class="text-base-content/85 line-clamp-2 mt-1 text-sm italic"
          data-testid="florist-note"
        >
          <.icon name="hero-chat-bubble-bottom-center-text" class="text-base-content/50 align-[-2px] mr-1 h-3.5 w-3.5" />{@order.florist_note}
        </p>

        <div
          :if={@order.gift or present?(@order.card_message)}
          class="text-base-content/75 mt-2 flex flex-wrap items-center gap-x-3 gap-y-2 text-xs"
        >
          <span :if={@order.gift} class="inline-flex min-w-0 items-baseline gap-1.5">
            <.icon name="hero-gift" class="h-3.5 w-3.5 shrink-0 self-center" />
            <span class="break-words">
              {if presence(@order.recipient_name),
                do: ~t"Gift for #{order_recipient_name = @order.recipient_name}",
                else: ~t"Gift order"}
            </span>
          </span>
          <span :if={present?(@order.card_message)} class="inline-flex items-center gap-1.5">
            <.icon name="hero-pencil-square" class="h-3.5 w-3.5 shrink-0" /> {~t"Card to write"}
          </span>
        </div>
      </.link>
      <div class="flex flex-wrap items-center gap-2 px-4 pt-1 pb-4 sm:px-5">
        <.badge :if={@order.missing_delivery_phone?} tone={:warning} icon="hero-phone-x-mark">
          {~t"Missing recipient phone"}
        </.badge>
        <.badge :if={@order.to_collect?} tone={:warning}>
          <%= if Decimal.positive?(@order.amount_paid) do %>
            {~t"To collect #{amount = Format.currency(@order.balance, Format.locale())}"}
          <% else %>
            {~t"Unpaid"}
          <% end %>
        </.badge>
        <.fulfillment_status_badge
          :if={!@order.can_mark_ready?}
          status={@order.fulfillment_status}
          method={@order.fulfillment_method}
        />
        <.button
          :if={@order.can_mark_ready?}
          type="button"
          variant="secondary"
          size="sm"
          phx-click="mark_ready"
          phx-value-id={@order.id}
          aria-label={~t"Mark order #{@order.order_reference} as ready"}
        >
          {~t"Mark as ready"}
        </.button>
      </div>
    </li>
    """
  end

  # Deliveries go out on a run, so they come first; the read already sorts each by time and distance.
  defp by_method(orders) do
    for method <- [:delivery, :pickup],
        group = Enum.filter(orders, &(&1.fulfillment_method == method)),
        group != [],
        do: {method, group}
  end

  defp method_heading(:delivery), do: ~t"Deliveries"
  defp method_heading(:pickup), do: ~t"Pickups"
end
