defmodule EdenflowersWeb.Admin.PromotionFormLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Pricing.Promotion
  alias Edenflowers.ShopTime
  alias EdenflowersWeb.Admin.PromotionsLive
  alias EdenflowersWeb.Layouts

  @history_fields [:name, :code, :discount_rate, :minimum_cart_total, :start_date, :expiration_date, :usage_limit]

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case load_form(params, actor) do
      {:ok, title, form} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:form, form)
         |> assign(:locale, Localize.get_locale())
         |> assign_history()}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Promotion not found.")
         |> push_navigate(to: PromotionsLive.default_path())}
    end
  end

  @impl true
  def render(assigns) do
    promotion_status = if assigns.form.source.type == :update, do: status(assigns.form.source.data)
    assigns = assign(assigns, :promotion_status, promotion_status)

    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={@page_title} back={{~t"Promotions", PromotionsLive.default_path()}} sticky>
          <:actions>
            <.button type="submit" form="promotion-form" variant="primary" size="sm" phx-disable-with={~t"Saving…"}>
              {~t"Save"}
            </.button>
          </:actions>
          <:menu>
            <.actions_menu :if={@form.source.type == :update} id="promotion-actions">
              <.actions_menu_button
                menu="promotion-actions"
                phx-click="delete"
                data-confirm={~t"Delete this promotion? This can't be undone."}
                class="text-error"
              >
                {~t"Delete"}
              </.actions_menu_button>
            </.actions_menu>
          </:menu>
        </.admin_page_header>

        <div class={["grid grid-cols-1 gap-6 xl:items-start", @history != [] && "xl:grid-cols-[minmax(0,1fr)_20rem] 2xl:grid-cols-[minmax(0,1fr)_24rem]"]}>
          <section
            :if={@form.source.type == :update}
            id="promotion-status"
            class="admin-card grid grid-cols-2 gap-4 p-4 sm:p-5 xl:col-start-1"
          >
            <div class="min-w-0">
              <h2 class="eyebrow text-base-content/75 mb-2">{~t"Status"}</h2>
              <.badge tone={elem(@promotion_status, 1)} icon={elem(@promotion_status, 2)}>
                {elem(@promotion_status, 0)}
              </.badge>
              <p :if={scheduled?(@form.source.data)} class="text-base-content/75 mt-2 text-sm tabular-nums">
                {~t"Starts"} {Format.date(@form.source.data.start_date, @locale)}
              </p>
            </div>
            <div id="promotion-usage" class="border-base-content/12 min-w-0 border-l pl-4 sm:pl-5">
              <h2 class="eyebrow text-base-content/75 mb-2">{~t"Used"}</h2>
              <p class="text-base-content tabular-nums">
                <span class="text-xl font-semibold">{@form.source.data.usage}</span>
                <span :if={@form.source.data.usage_limit} class="text-base-content/65 text-sm">
                  / {@form.source.data.usage_limit}
                </span>
              </p>
            </div>
          </section>
          <.form
            for={@form}
            id="promotion-form"
            data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
            phx-change="validate"
            phx-submit="save"
            class={["min-w-0 space-y-6 xl:col-start-1", @history == [] && "max-w-3xl"]}
          >
            <div class="admin-card divide-base-content/12 divide-y">
              <.form_section title={~t"Details"} joined>
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <.input field={@form[:name]} type="text" label={~t"Name"} class="input w-full" />
                  <div class="min-w-0">
                    <.input
                      field={@form[:code]}
                      type="text"
                      label={~t"Code"}
                      class="input font-mono w-full"
                      autocapitalize="characters"
                      autocorrect="off"
                      spellcheck="false"
                    />
                    <div class="mt-2 flex justify-end gap-2">
                      <.icon_button
                        phx-click="generate_code"
                        size="sm"
                        class="pointer-coarse:min-h-11 pointer-coarse:min-w-11"
                        title={~t"Generate code"}
                        aria_label={~t"Generate code"}
                      >
                        <.icon name="hero-arrow-path" class="h-4 w-4" />
                      </.icon_button>
                      <.copy_button
                        id="copy-promotion-code"
                        target={"##{@form[:code].id}"}
                        label={~t"Copy code"}
                        class="pointer-coarse:min-h-11 pointer-coarse:min-w-11"
                      />
                    </div>
                  </div>
                </div>
              </.form_section>

              <.form_section title={~t"Discount"} joined>
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <.input
                    field={@form[:discount_rate]}
                    value={rate_to_percent(@form[:discount_rate].value)}
                    type="text"
                    inputmode="decimal"
                    label={~t"Discount (%)"}
                    class="input w-full tabular-nums"
                  />
                  <.input
                    field={@form[:minimum_cart_total]}
                    type="text"
                    inputmode="decimal"
                    label={~t"Minimum cart total (€)"}
                    class="input w-full tabular-nums"
                  />
                </div>
              </.form_section>

              <.form_section title={~t"Validity and limits"} joined>
                <:description>{~t"Leave blank for no limit."}</:description>
                <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                  <.input field={@form[:start_date]} type="date" label={~t"Starts"} class="input w-full" />
                  <.input field={@form[:expiration_date]} type="date" label={~t"Expires"} class="input w-full" />
                  <.input
                    field={@form[:usage_limit]}
                    type="number"
                    min="1"
                    label={~t"Usage limit"}
                    class="input w-full tabular-nums"
                  />
                </div>
              </.form_section>
            </div>
          </.form>

          <aside :if={@history != []} class="flex flex-col gap-6 xl:col-start-2 xl:row-span-2 xl:row-start-1">
            <.widget id="promotion-history-widget" title={~t"History"}>
              <ol id="promotion-history" class="divide-base-content/12 divide-y text-sm">
                <.history_entry
                  :for={{entry, index} <- Enum.with_index(@history)}
                  id={"promotion-history-entry-#{index}"}
                  title={entry.title}
                  at={entry.at}
                  locale={@locale}
                >
                  <:details :if={entry.changes != []}>
                    <dl class="border-base-content/12 mt-1.5 mb-1 ml-0.5 space-y-2 border-l pl-3">
                      <div :for={{label, from, to} <- entry.changes}>
                        <dt class="text-base-content/75 text-xs">{label}</dt>
                        <dd class="text-base-content/85 break-words">{from} → {to}</dd>
                      </div>
                    </dl>
                  </:details>
                </.history_entry>
              </ol>
            </.widget>
          </aside>
        </div>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("generate_code", _params, socket) do
    form = socket.assigns.form
    params = Map.put(form.params, "code", Promotion.generate_code())
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, promotion} ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Promotion saved.")
         |> push_navigate(to: ~p"/admin/promotions/#{promotion.id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, ~t"The promotion wasn't saved. Check the fields marked below.")}
    end
  end

  def handle_event("delete", _params, socket) do
    case Ash.destroy(socket.assigns.form.source.data, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Promotion deleted.")
         |> push_navigate(to: PromotionsLive.default_path())}

      # Orders and newsletter subscribers keep a reference to the promotion.
      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           ~t"This promotion has been used, so it can't be deleted. Set an expiry date to stop it being used."
         )}
    end
  end

  defp load_form(%{"id" => id}, actor) do
    case Ash.get(Promotion, id, actor: actor, load: [:usage]) do
      {:ok, promotion} ->
        form = AshPhoenix.Form.for_update(promotion, :update, actor: actor, transform_params: &percent_to_rate/3)
        {:ok, promotion.name, to_form(form)}

      {:error, _} ->
        :error
    end
  end

  defp load_form(_params, actor) do
    form = AshPhoenix.Form.for_create(Promotion, :create, actor: actor, transform_params: &percent_to_rate/3)
    {:ok, ~t"New promotion", to_form(form)}
  end

  # The form asks for a percentage (15) but the resource stores a rate (0.15).
  # Submit runs this again over already-converted params, so only strings from the browser are converted.
  defp percent_to_rate(_form, %{"discount_rate" => percent} = params, _action) when is_binary(percent) do
    case Decimal.parse(String.trim(percent)) do
      {decimal, ""} -> Map.put(params, "discount_rate", Decimal.div(decimal, 100))
      _ -> params
    end
  end

  defp percent_to_rate(_form, params, _action), do: params

  defp rate_to_percent(%Decimal{} = rate),
    do: rate |> Decimal.mult(100) |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp rate_to_percent(value), do: value

  defp assign_history(socket) do
    history =
      case socket.assigns.form.source do
        %{type: :update, data: promotion} -> history(promotion, socket.assigns.locale)
        _ -> []
      end

    assign(socket, :history, history)
  end

  defp history(promotion, locale) do
    promotion
    |> Ash.load!(:paper_trail_versions, authorize?: false)
    |> Map.fetch!(:paper_trail_versions)
    |> Enum.map(&history_entry(&1, locale))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  defp history_entry(%{version_action_type: :create} = version, _locale),
    do: %{at: version.version_inserted_at, title: ~t"Created", changes: []}

  defp history_entry(version, locale) do
    changes =
      for field <- @history_fields, %{"from" => from, "to" => to} <- [version.changes[to_string(field)]] do
        {history_label(field), show(from, field, locale), show(to, field, locale)}
      end

    # A save that changed nothing still leaves a version.
    if changes != [], do: %{at: version.version_inserted_at, title: ~t"Edited", changes: changes}
  end

  defp history_label(:name), do: ~t"Name"
  defp history_label(:code), do: ~t"Code"
  defp history_label(:discount_rate), do: ~t"Discount"
  defp history_label(:minimum_cart_total), do: ~t"Minimum cart total"
  defp history_label(:start_date), do: ~t"Starts"
  defp history_label(:expiration_date), do: ~t"Expires"
  defp history_label(:usage_limit), do: ~t"Usage limit"

  defp status(promotion) do
    today = ShopTime.today()

    cond do
      scheduled?(promotion) ->
        {~t"Scheduled", :neutral, "hero-calendar-days"}

      promotion.expiration_date && Date.before?(promotion.expiration_date, today) ->
        {~t"Expired", :neutral, "hero-clock"}

      promotion.usage_limit && promotion.usage >= promotion.usage_limit ->
        {~t"Used up", :neutral, "hero-minus-circle"}

      true ->
        {~t"Active", :success, "hero-check"}
    end
  end

  defp scheduled?(%{start_date: nil}), do: false
  defp scheduled?(%{start_date: date}), do: Date.after?(date, ShopTime.today())

  defp show(nil, _field, _locale), do: "—"
  defp show(value, :discount_rate, locale), do: Format.percentage(Decimal.new(value), locale)
  defp show(value, :minimum_cart_total, locale), do: Format.currency(Decimal.new(value), locale)

  defp show(value, field, locale) when field in [:start_date, :expiration_date],
    do: Format.date(Date.from_iso8601!(value), locale)

  defp show(value, _field, _locale), do: to_string(value)
end
