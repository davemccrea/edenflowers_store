defmodule EdenflowersWeb.Admin.PromotionFormLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Admin.PromotionsLive
  alias EdenflowersWeb.Layouts
  alias Edenflowers.Format
  alias Edenflowers.Pricing.Promotion

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @history_fields [:name, :code, :discount_rate, :minimum_cart_total, :start_date, :expiration_date, :usage_limit]

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

  defp load_form(%{"id" => id}, actor) do
    case Ash.get(Promotion, id, actor: actor) do
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
  defp history_label(:usage_limit), do: ~t"Uses"

  defp show(nil, _field, _locale), do: "—"
  defp show(value, :discount_rate, locale), do: Format.percentage(Decimal.new(value), locale)
  defp show(value, :minimum_cart_total, locale), do: Format.currency(Decimal.new(value), locale)

  defp show(value, field, locale) when field in [:start_date, :expiration_date],
    do: Format.date(Date.from_iso8601!(value), locale)

  defp show(value, _field, _locale), do: to_string(value)

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
      {:ok, _promotion} ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Promotion saved.")
         |> push_navigate(to: PromotionsLive.default_path())}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="narrow">
        <.admin_page_header title={@page_title} back={PromotionsLive.default_path()} back_label={~t"Promotions"}>
          <:actions :if={@form.source.type == :update}>
            <div class="dropdown sm:dropdown-end">
              <.icon_button tabindex="0" size="sm" aria_label={~t"More actions"}>
                <.icon name="hero-ellipsis-horizontal" class="h-5 w-5" />
              </.icon_button>
              <ul tabindex="0" class="dropdown-content menu bg-base-100 border-base-300 z-10 mt-2 w-44 border p-1 shadow">
                <li>
                  <button
                    type="button"
                    phx-click="delete"
                    data-confirm={~t"Delete this promotion? This can't be undone."}
                    class="text-error"
                  >
                    {~t"Delete"}
                  </button>
                </li>
              </ul>
            </div>
          </:actions>
        </.admin_page_header>

        <.form for={@form} id="promotion-form" phx-change="validate" phx-submit="save" class="space-y-10">
          <.form_section title={~t"Promotion"}>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@form[:name]} type="text" label={~t"Name"} class="input w-full" />
              <div class="flex items-start gap-2">
                <div class="flex-1">
                  <.input
                    field={@form[:code]}
                    type="text"
                    label={~t"Code"}
                    help={~t"What customers type at checkout."}
                    class="input font-mono w-full"
                  />
                </div>
                <.icon_button
                  phx-click="generate_code"
                  size="sm"
                  class="mt-7"
                  title={~t"Generate code"}
                  aria_label={~t"Generate code"}
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4" />
                </.icon_button>
                <.copy_button
                  id="copy-promotion-code"
                  target={"##{@form[:code].id}"}
                  label={~t"Copy code"}
                  class="mt-7"
                />
              </div>
            </div>
          </.form_section>

          <.form_section title={~t"Discount"}>
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

          <.form_section title={~t"Limits"}>
            <:description>{~t"Leave blank for no limit."}</:description>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <.input field={@form[:start_date]} type="date" label={~t"Starts"} class="input w-full" />
              <.input field={@form[:expiration_date]} type="date" label={~t"Expires"} class="input w-full" />
              <.input
                field={@form[:usage_limit]}
                type="number"
                min="1"
                label={~t"Uses"}
                class="input w-full tabular-nums"
              />
            </div>
          </.form_section>

          <.button type="submit" variant="primary" class="w-full sm:w-auto">{~t"Save promotion"}</.button>
        </.form>

        <.form_section :if={@history != []} title={~t"History"} class="mt-10">
          <ol id="promotion-history" class="divide-base-content/8 divide-y text-sm">
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
                    <dt class="text-base-content/65 text-xs">{label}</dt>
                    <dd class="text-base-content/85 break-words">{from} → {to}</dd>
                  </div>
                </dl>
              </:details>
            </.history_entry>
          </ol>
        </.form_section>
      </.admin_page>
    </Layouts.admin>
    """
  end
end
