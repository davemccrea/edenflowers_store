defmodule EdenflowersWeb.Admin.FulfillmentsLive do
  @moduledoc """
  Admin fulfillments pages.

  `:index` shows the shop calendar, which every fulfillment option shares,
  with its same-day form, and lists the options with their prices in a table.
  `:edit` shows one option's prices form and, for a distance-priced option,
  a graph of what customers would pay at any distance with the prices as typed, beside
  what each delivery costs Jennie in car costs (`Fulfillment.DeliveryCost`).
  The costs help her set the prices; nothing charges them.

  The florist clicks dates / weekday headers on a calendar to enable or
  disable them. Click semantics live in `Edenflowers.Fulfillment.Availability`.
  Admin presentation lives in `EdenflowersWeb.AdminCalendar`. This LiveView
  only orchestrates state and persistence.

  Prices are edited through `:update_pricing`, which can't touch the option's
  method and rate type.
  """
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.AdminCalendar, only: [admin_calendar: 1, legend: 1]
  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts

  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.DeliveryCost
  alias EdenflowersWeb.AdminCalendar

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @fee_fields [:base_price, :price_per_km, :free_dist_km, :max_dist_km]
  @chart %{width: 600, height: 240, left: 44, right: 12, top: 12, bottom: 28}
  @steps_per_km 10

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:locale, Format.locale())
      |> assign(:today, Edenflowers.ShopTime.today())

    mount_action(socket.assigns.live_action, params, socket)
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Delivery and pickup"} />

        <.form_section title={~t"Calendar"}>
          <:description>{~t"Delivery and pickup share these days."}</:description>
          <.calendar calendar={@calendar} today={@today} />
        </.form_section>

        <.form_section title={~t"Same-day"} class="mt-6">
          <.same_day_form form={@same_day_form} />
        </.form_section>

        <.form_section title={~t"Options"} class="mt-6">
          <Cinder.collection
            id="fulfillment-options"
            query={Fulfillment.FulfillmentOption}
            action={:list_for_checkout}
            actor={@current_user}
            theme={EdenflowersWeb.Admin.CinderTheme}
            click={fn option -> JS.navigate(~p"/admin/fulfillments/#{option.id}") end}
          >
            <:col :let={option} field="name" label={~t"Name"}>
              <.link navigate={~p"/admin/fulfillments/#{option.id}"} class="font-medium hover:underline">
                {option.name}
              </.link>
            </:col>
            <:col :let={option} label={~t"Prices"}>
              <span class="tabular-nums">{price_summary(option, @locale)}</span>
            </:col>
          </Cinder.collection>
        </.form_section>
      </.admin_page>
    </Layouts.admin>
    """
  end

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@page_title} back={{~t"Delivery and pickup", ~p"/admin/fulfillments"}} />

        <%!-- On a wide screen the graph sits beside the prices, so it stays in view while they're typed. --%>
        <div class={@form.source.data.rate_type == :dynamic && "lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)] lg:grid lg:items-start lg:gap-6"}>
          <.form_section title={~t"Prices"}>
            <:description>{~t"Placed orders keep their fee unless you change their delivery."}</:description>
            <.pricing_form form={@form} rate_type={@form.source.data.rate_type} />
          </.form_section>

          <.form_section
            :if={@form.source.data.rate_type == :dynamic}
            title={~t"What customers pay"}
            class="mt-6 lg:sticky lg:top-6 lg:mt-0"
          >
            <.fee_preview saved={@form.source.data} draft={draft_option(@form)} />
          </.form_section>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"pricing" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"pricing" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, option} ->
        {:noreply,
         socket
         |> assign(:form, pricing_form(option, socket.assigns.current_user))
         |> push_event("admin-form-saved", %{id: "pricing-form"})
         |> put_flash(:info, ~t"Saved.")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, ~t"Not saved. Check the fields marked below.")}
    end
  end

  def handle_event("validate-same-day", %{"same_day" => params}, socket) do
    {:noreply, assign(socket, :same_day_form, AshPhoenix.Form.validate(socket.assigns.same_day_form, params))}
  end

  # Submitted against the current calendar, not the one the form was built
  # from, so the saved record doesn't undo calendar clicks made since.
  def handle_event("save-same-day", %{"same_day" => params}, socket) do
    form = same_day_form(socket.assigns.calendar, socket.assigns.current_user)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, calendar} ->
        {:noreply,
         socket
         |> assign_calendar(calendar)
         |> put_flash(:info, ~t"Saved.")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:same_day_form, form)
         |> put_flash(:error, ~t"Not saved. Check the fields marked below.")}
    end
  end

  def handle_event("reset-calendar", _, socket) do
    {:noreply, update_calendar(socket, &Fulfillment.reset_calendar!(&1, actor: &2))}
  end

  # Past days stay focusable for the keyboard, so the click is refused here.
  def handle_event("toggle-date", %{"date" => date}, socket) do
    date = Date.from_iso8601!(date)

    if Date.before?(date, socket.assigns.today) do
      {:noreply, socket}
    else
      {:noreply, update_calendar(socket, &Fulfillment.toggle_date!(&1, date, actor: &2))}
    end
  end

  def handle_event("toggle-weekday", %{"weekday" => weekday}, socket) do
    weekday = String.to_existing_atom(weekday)
    direction = if weekday in socket.assigns.calendar.available_days, do: :off, else: :on

    {:noreply, update_calendar(socket, &Fulfillment.set_weekday!(&1, weekday, direction, actor: &2))}
  end

  def handle_event("toggle-week", %{"week" => first}, socket) do
    %{calendar: calendar, today: today} = socket.assigns
    first = Date.from_iso8601!(first)
    week = Enum.map(0..6, &Date.add(first, &1))

    case AdminCalendar.week_toggle_direction(calendar, week, today) do
      nil ->
        {:noreply, socket}

      direction ->
        {:noreply, update_calendar(socket, &Fulfillment.set_week!(&1, week, today, direction, actor: &2))}
    end
  end

  defp mount_action(:index, _params, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Delivery and pickup")
     |> assign_calendar(Fulfillment.get_shop_calendar!(actor: socket.assigns.current_user))}
  end

  defp mount_action(:edit, %{"id" => id}, socket) do
    case Fulfillment.get_option_by_id(id, actor: socket.assigns.current_user) do
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Fulfillment option not found.")
         |> push_navigate(to: ~p"/admin/fulfillments")}

      {:ok, option} ->
        {:ok,
         socket
         |> assign(:page_title, option.name)
         |> assign(:form, pricing_form(option, socket.assigns.current_user))}
    end
  end

  attr :calendar, :any, required: true
  attr :today, Date, required: true

  defp calendar(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col gap-8 md:flex-row md:items-start">
      <div class="w-full min-w-0 max-w-xl">
        <.admin_calendar id="admin-fulfillment-calendar" calendar={@calendar} today={@today} />
      </div>

      <div class="flex min-w-0 flex-col gap-4">
        <.legend />
        <.button
          type="button"
          phx-click="reset-calendar"
          data-confirm={~t"Reset the calendar? All closed days reopen."}
          variant="destructive"
          size="sm"
          class="self-start"
        >
          <.icon name="hero-arrow-path" class="h-4 w-4" />
          {~t"Reset calendar"}
        </.button>
      </div>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true

  defp same_day_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="same-day-form"
      phx-change="validate-same-day"
      phx-submit="save-same-day"
      class="max-w-xl space-y-4"
    >
      <.input field={@form[:same_day]} type="checkbox" label={~t"Same-day fulfillment"} class="toggle toggle-primary" />
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <.input
          field={@form[:order_deadline]}
          type="time"
          label={~t"Same-day order deadline"}
          class="input w-full"
          hidden={not Phoenix.HTML.Form.normalize_value("checkbox", @form[:same_day].value)}
        />
      </div>
      <.button type="submit" variant="primary">{~t"Save"}</.button>
    </.form>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :rate_type, :atom, required: true

  defp pricing_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id="pricing-form"
      data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
      phx-change="validate"
      phx-submit="save"
      class="max-w-xl space-y-4"
    >
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-1 2xl:grid-cols-2">
        <.input
          field={@form[:base_price]}
          type="text"
          inputmode="decimal"
          label={~t"Base price (€)"}
          class="input w-full tabular-nums"
        />
        <%= if @rate_type == :dynamic do %>
          <.input
            field={@form[:price_per_km]}
            type="text"
            inputmode="decimal"
            label={~t"Price per km (€)"}
            class="input w-full tabular-nums"
          />
          <.input
            field={@form[:free_dist_km]}
            type="number"
            min="0"
            label={~t"Free delivery distance (km)"}
            help={~t"Bouquets marked Free delivery are delivered free within this distance."}
            class="input w-full tabular-nums"
          />
          <.input
            field={@form[:max_dist_km]}
            type="number"
            min="1"
            label={~t"Maximum distance (km)"}
            class="input w-full tabular-nums"
          />
        <% end %>
      </div>
      <div :if={@rate_type == :dynamic} class="space-y-4 pt-4">
        <h3 class="font-medium">{~t"Car costs"}</h3>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-1 2xl:grid-cols-2">
          <.input
            field={@form[:mileage_rate]}
            type="text"
            inputmode="decimal"
            label={~t"Kilometrikorvaus (€/km)"}
            class="input w-full tabular-nums"
          />
          <div class="hidden sm:block lg:hidden 2xl:block"></div>
          <.input
            field={@form[:fuel_price]}
            type="text"
            inputmode="decimal"
            label={~t"Petrol price (€/l)"}
            class="input w-full tabular-nums"
          />
          <.input
            field={@form[:fuel_consumption]}
            type="text"
            inputmode="decimal"
            label={~t"Fuel consumption (l/100 km)"}
            class="input w-full tabular-nums"
          />
        </div>
      </div>
      <.button type="submit" variant="primary">{~t"Save"}</.button>
    </.form>
    """
  end

  attr :saved, Fulfillment.FulfillmentOption, required: true
  attr :draft, Fulfillment.FulfillmentOption, required: true

  defp fee_preview(assigns) do
    %{saved: saved, draft: draft} = assigns
    changed? = Map.take(draft, @fee_fields) != Map.take(saved, @fee_fields)
    max_km = max(saved.max_dist_km, draft.max_dist_km)
    points = preview_points(saved, draft, changed?, max_km)

    top_value =
      points |> Enum.flat_map(&[&1.fee, &1.now, &1.car, &1.fuel]) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> 0 end)

    step = Enum.find([1, 2, 5, 10, 20, 50], 100, &(top_value / &1 <= 5))
    top = max(step, ceil(top_value / step) * step)
    plot_right = @chart.width - @chart.right
    plot_bottom = @chart.height - @chart.bottom

    x = fn km -> @chart.left + km / max_km * (plot_right - @chart.left) end
    y = fn value -> plot_bottom - value / top * (plot_bottom - @chart.top) end

    assigns =
      assign(assigns,
        c: @chart,
        x: x,
        y: y,
        changed?: changed?,
        points: points,
        steps_per_km: @steps_per_km,
        plot: %{
          left: @chart.left,
          right: plot_right,
          top: @chart.top,
          bottom: plot_bottom,
          maxKm: max_km,
          topValue: top
        },
        fee_ticks: Enum.to_list(0..top//step),
        km_ticks: Enum.to_list(0..max_km//2),
        paths: Map.new([:fee, :now, :car, :fuel], &{&1, line_path(points, &1, x, y)})
      )

    ~H"""
    <div
      id="fee-explorer"
      phx-hook="FeeExplorer"
      data-points={Jason.encode!(@points)}
      data-plot={Jason.encode!(@plot)}
      data-steps-per-km={@steps_per_km}
      data-not-delivered={~t"Not delivered"}
    >
      <dl aria-live="polite" class="mb-4 grid grid-cols-2 gap-x-6 gap-y-3 tabular-nums sm:grid-cols-4">
        <div>
          <dt class="text-base-content/65 text-xs">{~t"Distance"}</dt>
          <dd class="text-lg font-medium" data-value="km"></dd>
        </div>
        <div>
          <dt class="text-base-content/65 text-xs">{if @changed?, do: ~t"After saving", else: ~t"Fee"}</dt>
          <dd class="text-lg font-medium" data-value="fee"></dd>
        </div>
        <div :if={@changed?}>
          <dt class="text-base-content/65 text-xs">{~t"Now"}</dt>
          <dd class="text-base-content/70 text-lg" data-value="now"></dd>
        </div>
        <div :if={@paths.car}>
          <dt class="text-base-content/65 text-xs">{~t"Car cost"}</dt>
          <dd class="text-base-content/70 text-lg" data-value="car"></dd>
        </div>
        <div :if={@paths.fuel}>
          <dt class="text-base-content/65 text-xs">{~t"Fuel cost"}</dt>
          <dd class="text-base-content/70 text-lg" data-value="fuel"></dd>
        </div>
      </dl>

      <svg
        viewBox={"0 0 #{@c.width} #{@c.height}"}
        class="w-full cursor-crosshair touch-pan-y text-xs tabular-nums"
        role="img"
        aria-label={~t"Delivery fee by distance"}
      >
        <rect
          :if={@draft.free_dist_km > 0}
          x={@x.(0)}
          y={@c.top}
          width={@x.(@draft.free_dist_km) - @x.(0)}
          height={@plot.bottom - @c.top}
          class="fill-success/10"
        />
        <g :for={fee <- @fee_ticks}>
          <line x1={@c.left} x2={@plot.right} y1={@y.(fee)} y2={@y.(fee)} class="stroke-base-300" />
          <text x={@c.left - 6} y={@y.(fee) + 4} text-anchor="end" class="fill-base-content/60">{fee} €</text>
        </g>
        <text
          :for={km <- @km_ticks}
          x={@x.(km)}
          y={@c.height - 8}
          text-anchor="middle"
          class="fill-base-content/60"
        >
          {km}
        </text>
        <path
          :if={@paths.now}
          d={@paths.now}
          fill="none"
          stroke-width="2"
          stroke-dasharray="4 4"
          class="stroke-base-content/40"
        />
        <path :if={@paths.car} d={@paths.car} fill="none" stroke-width="2" class="stroke-error/70" />
        <path :if={@paths.fuel} d={@paths.fuel} fill="none" stroke-width="2" class="stroke-warning" />
        <path d={@paths.fee} fill="none" stroke-width="2.5" class="stroke-primary" />
        <line data-cursor y1={@c.top} y2={@plot.bottom} class="stroke-base-content/50" stroke-width="1" />
        <circle :if={@paths.now} data-dot="now" r="3.5" class="fill-base-content/40" />
        <circle :if={@paths.car} data-dot="car" r="3.5" class="fill-error" />
        <circle :if={@paths.fuel} data-dot="fuel" r="3.5" class="fill-warning" />
        <circle data-dot="fee" r="4.5" class="fill-primary" />
      </svg>

      <input
        id="fee-explorer-distance"
        type="range"
        min="0"
        max={@plot.maxKm}
        step="1"
        value="5"
        aria-label={~t"Distance in km"}
        class="range range-xs range-primary mt-2 block"
        style={"margin-left: #{@c.left / @c.width * 100}%; width: #{(@plot.right - @c.left) / @c.width * 100}%"}
      />

      <div class="text-base-content/70 mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs">
        <span class="inline-flex items-center gap-1.5">
          <span class="bg-primary h-0.5 w-4"></span>{if @changed?, do: ~t"After saving", else: ~t"Fee"}
        </span>
        <span :if={@paths.now} class="inline-flex items-center gap-1.5">
          <span class="border-base-content/40 w-4 border-t-2 border-dashed"></span>{~t"Now"}
        </span>
        <span :if={@paths.car} class="inline-flex items-center gap-1.5">
          <span class="bg-error/70 h-0.5 w-4"></span>{~t"Car cost"}
        </span>
        <span :if={@paths.fuel} class="inline-flex items-center gap-1.5">
          <span class="bg-warning h-0.5 w-4"></span>{~t"Fuel cost"}
        </span>
        <span :if={@draft.free_dist_km > 0} class="inline-flex items-center gap-1.5">
          <span class="bg-success/20 h-3 w-4"></span>{~t"Free delivery"}
        </span>
      </div>
      <p :if={@paths.car || @paths.fuel} class="text-base-content/70 mt-2 text-xs">
        {~t"Costs count the drive there and back, but not your time."}
      </p>
    </div>
    """
  end

  # The fee and costs every tenth of a km, from the same calculations as
  # checkout. The FeeExplorer hook only reads them, so prices are still worked
  # out in one place. A fee is nil where that option no longer delivers.
  defp preview_points(saved, draft, changed?, max_km) do
    for step <- 0..(max_km * @steps_per_km) do
      metres = div(step * 1000, @steps_per_km)

      %{
        fee: to_float(Fulfillment.Fee.calculate(draft, metres).fulfillment_fee),
        now: if(changed?, do: to_float(Fulfillment.Fee.calculate(saved, metres).fulfillment_fee)),
        car: to_float(DeliveryCost.mileage(draft, metres)),
        fuel: to_float(DeliveryCost.fuel(draft, metres))
      }
    end
  end

  defp to_float(nil), do: nil
  defp to_float(decimal), do: Decimal.to_float(decimal)

  # Stops at the first point without a value, where that option stops delivering.
  defp line_path(points, key, x, y) do
    case Enum.take_while(Enum.with_index(points), fn {point, _} -> point[key] end) do
      [] ->
        nil

      plotted ->
        Enum.map_join(plotted, " ", fn {point, step} ->
          command = if step == 0, do: "M", else: "L"
          "#{command}#{Float.round(x.(step / @steps_per_km) / 1, 1)},#{Float.round(y.(point[key]) / 1, 1)}"
        end)
    end
  end

  # The option with the prices as typed. A field that's empty or doesn't parse
  # keeps its saved value, so a half-typed price doesn't break the graph.
  defp draft_option(form) do
    changeset = form.source.source
    saved = form.source.data

    Enum.reduce(@fee_fields ++ [:mileage_rate, :fuel_price, :fuel_consumption], saved, fn field, option ->
      case Ash.Changeset.get_attribute(changeset, field) do
        nil -> option
        value -> Map.put(option, field, value)
      end
    end)
  end

  defp price_summary(option, locale) do
    distance =
      if option.rate_type == :dynamic do
        [
          ~t"#{price = Format.currency(option.price_per_km, locale)}/km",
          ~t"free within #{km = option.free_dist_km} km",
          ~t"up to #{km = option.max_dist_km} km"
        ]
      else
        []
      end

    Enum.join([Format.currency(option.base_price, locale)] ++ distance, " · ")
  end

  defp pricing_form(option, actor) do
    option
    |> AshPhoenix.Form.for_update(:update_pricing, actor: actor, as: "pricing")
    |> to_form()
  end

  defp assign_calendar(socket, calendar) do
    socket
    |> assign(:calendar, calendar)
    |> assign(:same_day_form, same_day_form(calendar, socket.assigns.current_user))
  end

  defp same_day_form(calendar, actor) do
    calendar
    |> AshPhoenix.Form.for_update(:update_same_day, actor: actor, as: "same_day")
    |> to_form()
  end

  # Leaves the same-day form alone, so a click on the calendar keeps its unsaved edits.
  defp update_calendar(socket, fun) do
    assign(socket, :calendar, fun.(socket.assigns.calendar, socket.assigns.current_user))
  end
end
