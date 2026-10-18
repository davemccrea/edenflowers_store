defmodule EdenflowersWeb.Admin.FulfillmentsLive do
  @moduledoc """
  Admin fulfillments pages.

  `:index` shows the shop calendar, which every fulfillment option shares,
  with its same-day form, and lists the options with their prices in a table.
  `:edit` shows one option's prices form.

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
  alias EdenflowersWeb.AdminCalendar

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

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
        <.admin_page_header title={~t"Fulfillments"} />

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
        <.admin_page_header title={@page_title} back={{~t"Fulfillments", ~p"/admin/fulfillments"}} />

        <.form_section title={~t"Prices"}>
          <:description>{~t"Placed orders keep their fee unless you change their delivery."}</:description>
          <.pricing_form form={@form} rate_type={@form.source.data.rate_type} />
        </.form_section>
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
     |> assign(:page_title, ~t"Fulfillments")
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
          variant="ghost"
          size="sm"
          class="text-error self-start"
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
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
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
            help={~t"Only the base price is charged within this distance."}
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
      <.button type="submit" variant="primary">{~t"Save"}</.button>
    </.form>
    """
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
