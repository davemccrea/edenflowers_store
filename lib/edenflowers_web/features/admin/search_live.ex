defmodule EdenflowersWeb.Admin.SearchLive do
  @moduledoc """
  Back-office search across orders, customers, subscriptions, invoices, course bookings, courses and
  promotion codes.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Accounts
  alias Edenflowers.Courses
  alias Edenflowers.Events
  alias Edenflowers.Format
  alias Edenflowers.Orders
  alias Edenflowers.Payments
  alias Edenflowers.Pricing
  alias Edenflowers.Translations
  alias EdenflowersWeb.Admin.InvoicesLive
  alias EdenflowersWeb.Admin.PromotionFormLive
  alias EdenflowersWeb.Admin.PubSub
  alias EdenflowersWeb.Checkout.Fields
  alias EdenflowersWeb.Layouts
  alias Phoenix.LiveView.AsyncResult

  @limit 10
  @sections [:orders, :customers, :subscriptions, :invoices, :bookings, :courses, :promotions]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PubSub.subscribe([
        Events.admin_orders(),
        Events.admin_customers(),
        Events.admin_subscriptions(),
        Events.admin_invoices(),
        Events.admin_bookings(),
        Events.admin_courses(),
        Events.admin_promotions()
      ])
    end

    {:ok,
     socket
     |> assign(locale: Localize.get_locale(), limit: @limit, today: Edenflowers.ShopTime.today())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    term = String.trim(params["q"] || "")

    {:noreply,
     socket
     |> assign(:page_title, ~t"Search")
     |> assign(:term, term)
     |> load_results(reset: true)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket),
    do: {:noreply, PubSub.schedule_refresh(socket, :search)}

  # A refresh keeps the results on screen while it loads. One arriving before the first results
  # is dropped, so it can't restart a search that is still running.
  def handle_info({:admin_refresh, :search}, socket) do
    if socket.assigns.results.ok?, do: {:noreply, load_results(socket, reset: false)}, else: {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user} search_term={@term}>
      <.admin_page>
        <.admin_page_header title={~t"Search"} />

        <.async_result :let={results} assign={@results}>
          <:loading><.results_skeleton /></:loading>
          <:failed :let={_failure}>
            <.widget id="search-failed" title={~t"The search didn't finish"}>
              <p class="text-base-content/75 text-sm">{~t"Search again in a moment."}</p>
            </.widget>
          </:failed>
          <.results results={results} term={@term} limit={@limit} locale={@locale} today={@today} />
        </.async_result>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :results, :map, required: true
  attr :term, :string, required: true
  attr :limit, :integer, required: true
  attr :locale, :string, required: true
  attr :today, Date, required: true

  defp results(assigns) do
    found = for section <- @sections, assigns.results[section] != [], do: {section, assigns.results[section]}
    assigns = assigns |> assign(assigns.results) |> assign(found: found, found?: found != [])

    ~H"""
    <.widget
      :if={not @found?}
      id="search-empty"
      title={if @term == "", do: ~t"Nothing searched yet", else: ~t"No results for “#{term = @term}”"}
    >
      <p class="text-base-content/75 text-sm">
        {~t"Try a name, email, phone number, order number or code."}
      </p>
    </.widget>

    <nav
      :if={length(@found) > 1}
      aria-label={~t"Results by kind"}
      class="mb-6 flex flex-wrap gap-x-5 gap-y-1 text-sm"
    >
      <a :for={{section, results} <- @found} href={"#search-#{section}"} class="link-underline-hover touch-target">
        {section_title(section)}
        <span class="text-base-content/75 tabular-nums">{count_label(results, @limit)}</span>
      </a>
    </nav>

    <div :if={@found?} class="flex flex-col gap-6">
      <.result_box section={:orders} rows={@orders} limit={@limit} href={fn order -> ~p"/admin/orders/#{order.id}" end}>
        <:who :let={order}>
          <span class={title_class()}><.match text={order.customer_name || ~t"Unnamed customer"} term={@term} /></span>
          <span class={detail_class()}>
            <.match text={order.order_reference} term={@term} />
            <span :if={order.gift and order.recipient_name}>
              · <.icon name="hero-gift" class="align-[-0.15em] h-3.5 w-3.5" />
              <span class="sr-only">{~t"Gift for"}</span>
              <.match text={order.recipient_name} term={@term} />
            </span>
          </span>
        </:who>
        <:facts :let={order}>{facts(order_facts(order, @locale))}</:facts>
        <:status :let={order}>
          <.fulfillment_status_badge status={order.fulfillment_status} method={order.fulfillment_method} />
          <.order_payment_badge order={order} locale={@locale} />
        </:status>
        <:see_all navigate={~p"/admin/orders?#{%{search: @term}}"}>{~t"See all matching orders"}</:see_all>
      </.result_box>

      <.result_box
        section={:customers}
        rows={@customers}
        limit={@limit}
        href={fn customer -> ~p"/admin/customers/#{customer.id}" end}
      >
        <:who :let={customer}>
          <span class={title_class()}><.match text={customer.name || to_string(customer.email)} term={@term} /></span>
          <span :if={customer.name} class={detail_class()}>
            <.match text={to_string(customer.email)} term={@term} />
          </span>
        </:who>
        <:facts :let={customer}>{facts(customer_facts(customer, @locale))}</:facts>
        <:see_all navigate={~p"/admin/customers?#{%{search: @term}}"}>{~t"See all matching customers"}</:see_all>
      </.result_box>

      <.result_box
        section={:subscriptions}
        rows={@subscriptions}
        limit={@limit}
        href={fn subscription -> ~p"/admin/subscriptions/#{subscription.id}" end}
      >
        <:who :let={subscription}>
          <span class={title_class()}><.match text={subscription.user.name || ~t"Unnamed customer"} term={@term} /></span>
          <span class={detail_class()}><.match text={to_string(subscription.user.email)} term={@term} /></span>
        </:who>
        <:facts :let={subscription}>{facts(subscription_facts(subscription, @locale))}</:facts>
        <:status :let={subscription}><.subscription_state_badge state={subscription.state} /></:status>
        <:see_all navigate={~p"/admin/subscriptions?#{%{search: @term}}"}>
          {~t"See all matching subscriptions"}
        </:see_all>
      </.result_box>

      <.result_box
        section={:invoices}
        rows={@invoices}
        limit={@limit}
        href={fn invoice -> ~p"/admin/invoices/#{invoice.id}" end}
      >
        <:who :let={invoice}>
          <span class={title_class()}><.match text={invoice.buyer || ~t"Customer details needed"} term={@term} /></span>
          <span :if={invoice.number} class={detail_class()}>
            <.match text={to_string(invoice.number)} term={@term} />
          </span>
        </:who>
        <:facts :let={invoice}>{facts(invoice_facts(invoice, @locale))}</:facts>
        <:status :let={invoice}>
          <.badge tone={InvoicesLive.status_tone(invoice.status, invoice.overdue?)}>
            {InvoicesLive.status_label(invoice.status, invoice.overdue?)}
          </.badge>
        </:status>
        <:see_all navigate={~p"/admin/invoices?#{%{search: @term}}"}>{~t"See all matching invoices"}</:see_all>
      </.result_box>

      <.result_box
        section={:bookings}
        rows={@bookings}
        limit={@limit}
        href={fn booking -> ~p"/admin/courses/#{booking.course_id}?#{%{booking: booking.id}}" end}
      >
        <:who :let={booking}>
          <span class={title_class()}><.match text={booking.name} term={@term} /></span>
          <span class={detail_class()}><.match text={to_string(booking.email)} term={@term} /></span>
        </:who>
        <:facts :let={booking}>{facts(booking_facts(booking, @locale))}</:facts>
        <:status :let={booking}>
          <.badge :if={booking.cancelled?} tone={:neutral}>{dpgettext("admin", "booking", "Cancelled")}</.badge>
        </:status>
      </.result_box>

      <.result_box section={:courses} rows={@courses} limit={@limit} href={fn course -> ~p"/admin/courses/#{course.id}" end}>
        <:who :let={course}>
          <span class={title_class()}><.match text={Translations.translate(course).name} term={@term} /></span>
          <span class={detail_class()}>
            {Format.date(course.date, @locale)} · {Format.time(course.start_time, @locale)}–{Format.time(
              course.end_time,
              @locale
            )}
          </span>
        </:who>
        <:facts :let={course}>
          {~t"#{booked = course.seats_booked || 0} of #{total = course.total_places} seats booked"}
        </:facts>
        <:status :let={course}>
          <.badge :if={course.draft} tone={:neutral}>{~t"Draft"}</.badge>
          <.badge :if={Date.before?(course.date, @today)} tone={:tag}>{dpgettext("admin", "course", "Past")}</.badge>
        </:status>
      </.result_box>

      <.result_box
        section={:promotions}
        rows={@promotions}
        limit={@limit}
        href={fn promotion -> ~p"/admin/promotions/#{promotion.id}" end}
      >
        <:who :let={promotion}>
          <span class={title_class()}><.match text={to_string(promotion.code)} term={@term} /></span>
          <span class={detail_class()}>{promotion.name}</span>
        </:who>
        <:facts :let={promotion}>{facts(promotion_facts(promotion, @locale))}</:facts>
        <:status :let={promotion}><.promotion_status status={promotion.status} /></:status>
        <:see_all navigate={~p"/admin/promotions?#{%{search: @term}}"}>{~t"See all matching promotions"}</:see_all>
      </.result_box>
    </div>
    """
  end

  attr :section, :atom, required: true
  attr :rows, :list, required: true
  attr :limit, :integer, required: true
  attr :href, :any, required: true, doc: "fn row -> the path the row opens"
  slot :who, required: true, doc: "the row's name and the line under it"
  slot :facts
  slot :status, doc: "badges"

  slot :see_all, doc: "shown once the box is full, since there may be more" do
    attr :navigate, :string, required: true
  end

  # One kind of result. Hidden when it has no rows.
  defp result_box(assigns) do
    ~H"""
    <.widget
      :if={@rows != []}
      id={"search-#{@section}"}
      title={section_title(@section)}
      count={shown_count(@rows, @limit)}
      class="scroll-mt-24"
    >
      <ul class={list_class()}>
        <li :for={row <- @rows} class={item_class()}>
          <.link navigate={@href.(row)} class={row_class()}>
            <span class="min-w-0">{render_slot(@who, row)}</span>
            <span class="text-base-content/75 min-w-0 text-sm tabular-nums max-sm:row-start-2 sm:truncate">
              {render_slot(@facts, row)}
            </span>
            <span class="flex items-center justify-end gap-2 max-sm:col-start-2 max-sm:row-span-2 max-sm:row-start-1 max-sm:flex-col max-sm:items-end">
              {render_slot(@status, row)}
            </span>
          </.link>
        </li>
      </ul>
      <.link
        :for={see_all <- @see_all}
        :if={length(@rows) == @limit}
        navigate={see_all.navigate}
        class="link link-primary touch-target mt-3 inline-block text-sm"
      >
        {render_slot(see_all)}
      </.link>
    </.widget>
    """
  end

  # Stands in for the result boxes while a search runs, in the same three-zone rows. It fades in
  # after 300ms, like the loading bar and button spinners, so a quick search never flashes it.
  defp results_skeleton(assigns) do
    ~H"""
    <div
      id="search-loading"
      role="status"
      class="[animation:admin-page-fade-in_150ms_ease-out_300ms_backwards] flex flex-col gap-6"
    >
      <span class="sr-only">{~t"Searching…"}</span>
      <section :for={rows <- [4, 3]} class="admin-card p-4 motion-safe:animate-pulse sm:p-5" aria-hidden="true">
        <div class="bg-base-300 mb-6 h-4 w-28"></div>
        <ul class={list_class()}>
          <li :for={_row <- 1..rows} class={item_class()}>
            <div class={["py-3", row_class()]}>
              <span class="space-y-2">
                <span class="bg-base-300 block h-4 w-40 max-w-full"></span>
                <span class="bg-base-200 block h-3 w-24"></span>
              </span>
              <span class="bg-base-200 block h-3 w-56 max-w-full max-sm:row-start-2 max-sm:mt-2"></span>
              <span class="bg-base-200 block h-5 w-16 justify-self-end rounded-full"></span>
            </div>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp section_title(:orders), do: ~t"Orders"
  defp section_title(:customers), do: ~t"Customers"
  defp section_title(:subscriptions), do: ~t"Subscriptions"
  defp section_title(:invoices), do: ~t"Invoices"
  defp section_title(:bookings), do: ~t"Course bookings"
  defp section_title(:courses), do: ~t"Courses"
  defp section_title(:promotions), do: ~t"Promotions"

  # Every box shares one column template whose first column doesn't depend on the badges' width,
  # so who, facts and status line up down the whole page.
  # On phones a row stacks instead: who, then facts, with the status beside them.
  defp list_class do
    "divide-base-content/12 -my-2 divide-y sm:grid sm:grid-cols-[35%_minmax(0,1fr)_auto] sm:gap-x-6 xl:grid-cols-[20rem_minmax(0,1fr)_auto]"
  end

  defp item_class, do: "sm:col-span-full sm:grid sm:grid-cols-subgrid"

  defp row_class do
    "group grid-cols-[minmax(0,1fr)_auto] grid items-center gap-x-4 py-2.5 sm:col-span-full sm:grid-cols-subgrid sm:gap-x-6"
  end

  defp title_class, do: "text-base-content link-underline-group-hover block truncate"
  defp detail_class, do: "text-base-content/75 block truncate text-sm tabular-nums"
  defp facts(facts), do: facts |> Enum.filter(& &1) |> Enum.join(" · ")

  defp order_facts(order, locale) do
    [
      if(order.gift_voucher_sale?, do: ~t"Gift voucher", else: Format.date(order.fulfillment_date, locale)),
      Format.currency(order.grand_total, locale)
    ]
  end

  defp customer_facts(customer, locale) do
    [
      ~t"#{count = customer.placed_order_count} order(s)"N,
      Format.currency(customer.total_spent, locale),
      customer.last_ordered_at && ~t"Last order #{date = Format.date(customer.last_ordered_at, locale)}"
    ]
  end

  defp subscription_facts(subscription, locale) do
    [
      variant_size_label(subscription.product_variant.size),
      Fields.interval_label(subscription.interval_weeks),
      subscription.next_delivery_date &&
        ~t"Next delivery #{date = Format.date(subscription.next_delivery_date, locale)}"
    ]
  end

  defp invoice_facts(%{number: nil}, _locale), do: []

  defp invoice_facts(invoice, locale) do
    [
      Format.currency(invoice.amount, locale),
      invoice.due_date && ~t"Due #{date = Format.date(invoice.due_date, locale)}"
    ]
  end

  defp booking_facts(booking, locale) do
    [
      Translations.translate(booking.course).name,
      Format.date(booking.course.date, locale),
      ~t"#{count = booking.seats_held} seat(s)"N
    ]
  end

  defp promotion_facts(promotion, locale) do
    [
      Format.percentage(promotion.discount_rate, locale),
      ~t"Used #{usage = promotion_usage(promotion)}",
      promotion.expiration_date && ~t"Expires #{date = Format.date(promotion.expiration_date, locale)}"
    ]
  end

  defp promotion_usage(%{usage_limit: nil, usage: usage}), do: to_string(usage)
  defp promotion_usage(%{usage_limit: limit, usage: usage}), do: "#{usage} / #{limit}"

  attr :status, :atom, required: true

  defp promotion_status(assigns) do
    {label, tone, _icon} = PromotionFormLive.status(assigns.status)
    assigns = assign(assigns, label: label, tone: tone)

    ~H"""
    <.badge tone={@tone}>{@label}</.badge>
    """
  end

  attr :text, :string, required: true
  attr :term, :string, required: true

  # Sets the term in the heavier weight where it appears, so a row shows why it matched. A match
  # in a field the row doesn't show, like an order's phone number, marks nothing.
  defp match(assigns) do
    # to_string: a field can be empty, like the reference of an order written straight to the database.
    parts = Regex.split(~r/#{Regex.escape(assigns.term)}/iu, to_string(assigns.text), include_captures: true)
    assigns = assign(assigns, :parts, Enum.with_index(parts))

    ~H"""
    <span :for={{part, index} <- @parts} class={rem(index, 2) == 1 && "text-base-content font-semibold"}>{part}</span>
    """
  end

  # Runs off the LiveView process, so the page shows its skeleton at once on a slow server.
  defp load_results(%{assigns: %{term: ""}} = socket, _opts) do
    assign(socket, :results, AsyncResult.ok(Map.new(@sections, &{&1, []})))
  end

  defp load_results(socket, opts) do
    term = socket.assigns.term
    search_opts = [actor: socket.assigns.current_user, query: [limit: @limit]]

    assign_async(
      socket,
      :results,
      fn ->
        {:ok,
         %{
           results: %{
             orders: Orders.search_orders!(term, search_opts),
             customers:
               Accounts.search_customers!(
                 term,
                 search_opts ++ [load: [:placed_order_count, :total_spent, :last_ordered_at]]
               ),
             subscriptions: Orders.search_subscriptions!(term, search_opts),
             invoices: Payments.search_invoices!(term, search_opts),
             bookings: Courses.search_registrations!(term, search_opts),
             courses: Courses.search_courses!(term, search_opts),
             promotions: Pricing.search_promotions_by_code!(term, search_opts)
           }
         }}
      end,
      opts
    )
  end

  # At the limit the count is only the page size, and "See all" says there are more.
  defp shown_count(results, limit), do: if(length(results) < limit, do: length(results))
  defp count_label(results, limit), do: shown_count(results, limit) || "#{limit}+"
end
