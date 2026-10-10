defmodule EdenflowersWeb.Admin.FulfillmentsLive do
  @moduledoc """
  Admin fulfillments pages.

  `:index` shows one calendar for every fulfillment option at once (with a
  `:mixed` indicator when options disagree) and lists the options with their
  prices. `:edit` shows one option's prices form and a calendar for just that
  option.

  The florist clicks dates / weekday headers on a calendar to enable or
  disable them. Click semantics live in `Edenflowers.Fulfillment.Availability`.
  Admin presentation lives in `EdenflowersWeb.Admin.Calendar`. This LiveView
  only orchestrates state and persistence.

  Prices are edited through `:update_pricing`, which can't touch the calendar
  or the option's method and rate type.
  """
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Calendar, only: [grid: 1, legend: 1]
  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts

  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias EdenflowersWeb.Admin.CalendarViewModel

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @timezone "Europe/Helsinki"

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:options, Fulfillment.list_options!())
      |> assign(:locale, Format.locale())
      |> assign(:today, today())

    mount_action(socket.assigns.live_action, params, socket)
  end

  defp mount_action(:index, _params, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Fulfillments")
     |> assign(:scope, :all)}
  end

  defp mount_action(:edit, %{"id" => id}, socket) do
    case Enum.find(socket.assigns.options, &(&1.id == id)) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Fulfillment option not found.")
         |> push_navigate(to: ~p"/admin/fulfillments")}

      option ->
        {:ok,
         socket
         |> assign(:page_title, option.name)
         |> assign(:scope, option.id)
         |> assign(:form, pricing_form(option, socket.assigns.current_user))}
    end
  end

  @impl true
  def render(%{live_action: :index} = assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header title={~t"Fulfillments"} />

        <.form_section title={~t"Calendar"}>
          <:description>{~t"Changes here apply to every option."}</:description>
          <.calendar scope={@scope} options={@options} today={@today} />
        </.form_section>

        <.form_section title={~t"Options"} class="mt-10">
          <:description>{~t"Open an option to change its prices or its own calendar."}</:description>
          <ul id="fulfillment-options" class="divide-base-content/8 divide-y">
            <li :for={option <- @options}>
              <.link
                navigate={~p"/admin/fulfillments/#{option.id}"}
                class="-mx-2 flex items-center justify-between gap-4 rounded px-2 py-3 hover:bg-base-200"
              >
                <div class="min-w-0">
                  <p class="text-base-content font-medium">{option.name}</p>
                  <p class="text-base-content/65 text-sm tabular-nums">{price_summary(option, @locale)}</p>
                </div>
                <.icon name="hero-chevron-right" class="text-base-content/50 h-4 w-4 shrink-0" />
              </.link>
            </li>
          </ul>
        </.form_section>
      </.admin_page>
    </Layouts.admin>
    """
  end

  def render(%{live_action: :edit} = assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="wide">
        <.admin_page_header title={@page_title} back={~p"/admin/fulfillments"} back_label={~t"Fulfillments"} />

        <.form_section title={~t"Prices"}>
          <:description>{~t"New prices apply to the next delivery quote. Placed orders keep their fee."}</:description>
          <.pricing_form form={@form} rate_type={@form.source.data.rate_type} />
        </.form_section>

        <.form_section title={~t"Calendar"} class="mt-10">
          <.calendar scope={@scope} options={@options} today={@today} />
        </.form_section>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :scope, :any, required: true
  attr :options, :list, required: true
  attr :today, Date, required: true

  defp calendar(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col gap-8 md:flex-row md:items-start">
      <div class="w-full min-w-0 max-w-xl">
        <.grid id="admin-fulfillment-calendar" scope={@scope} options={@options} today={@today} />
      </div>

      <div class="flex min-w-0 flex-col gap-4">
        <.legend scope={@scope} />
        <.button
          type="button"
          phx-click="reset-calendar"
          data-confirm={reset_confirm_message(@scope, @options)}
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
  attr :rate_type, :atom, required: true

  defp pricing_form(assigns) do
    ~H"""
    <.form for={@form} id="pricing-form" phx-change="validate" phx-submit="save" class="max-w-xl space-y-4">
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
            help={~t"Free-delivery products cost only the base price within this distance."}
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
      <.input field={@form[:same_day]} type="checkbox" label={~t"Same-day fulfillment"} />
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <.input field={@form[:order_deadline]} type="time" label={~t"Same-day order deadline"} class="input w-full" />
      </div>
      <.button type="submit" variant="primary">{~t"Save prices"}</.button>
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

    same_day =
      if option.same_day,
        do: [~t"same day until #{time = Format.time(option.order_deadline, locale)}"],
        else: []

    Enum.join([Format.currency(option.base_price, locale)] ++ distance ++ same_day, " · ")
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
         |> replace_options([option])
         |> assign(:form, pricing_form(option, socket.assigns.current_user))
         |> put_flash(:info, ~t"Prices saved.")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("reset-calendar", _, socket) do
    {:noreply, apply_to_scope(socket, &Fulfillment.reset_calendar!(&1, actor: &2))}
  end

  @impl true
  def handle_info({:fulfillment_date_toggled, date}, socket) do
    {:noreply, apply_to_scope(socket, &Fulfillment.toggle_date!(&1, date, actor: &2))}
  end

  def handle_info({:fulfillment_weekday_toggled, weekday}, socket) do
    targets = scoped_options(socket)
    direction = CalendarViewModel.weekday_toggle_direction(targets, weekday)

    {:noreply, apply_to_scope(socket, &Fulfillment.set_weekday!(&1, weekday, direction, actor: &2))}
  end

  def handle_info({:fulfillment_week_toggled, week}, socket) do
    %{today: today} = socket.assigns
    targets = scoped_options(socket)

    case CalendarViewModel.week_toggle_direction(targets, week, today) do
      nil ->
        {:noreply, socket}

      direction ->
        {:noreply, apply_to_scope(socket, &Fulfillment.set_week!(&1, week, today, direction, actor: &2))}
    end
  end

  defp pricing_form(option, actor) do
    option
    |> AshPhoenix.Form.for_update(:update_pricing, actor: actor, as: "pricing")
    |> to_form()
  end

  defp scoped_options(%{assigns: %{scope: scope, options: options}}),
    do: CalendarViewModel.scoped_options(scope, options)

  defp apply_to_scope(socket, fun) do
    actor = socket.assigns.current_user
    replace_options(socket, Enum.map(scoped_options(socket), &fun.(&1, actor)))
  end

  defp replace_options(socket, updated) do
    updated_by_id = Map.new(updated, &{&1.id, &1})
    update(socket, :options, fn options -> Enum.map(options, &Map.get(updated_by_id, &1.id, &1)) end)
  end

  defp today, do: @timezone |> DateTime.now!() |> DateTime.to_date()

  defp reset_confirm_message(:all, _options),
    do: ~t"Reset every fulfillment option? All weekdays and dates reopen, and your closed days are lost."

  defp reset_confirm_message(option_id, options) do
    name = options |> Enum.find(&(&1.id == option_id)) |> Map.fetch!(:name)
    ~t"Reset #{name}? All weekdays and dates reopen, and your closed days are lost."
  end
end
