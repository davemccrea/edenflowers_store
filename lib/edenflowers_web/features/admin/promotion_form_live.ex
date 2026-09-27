defmodule EdenflowersWeb.Admin.PromotionFormLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Admin.PromotionsLive
  alias EdenflowersWeb.Layouts
  alias Edenflowers.Pricing.Promotion

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case load_form(params, actor) do
      {:ok, title, form} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:form, form)}

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
  defp percent_to_rate(_form, params, _action) do
    Map.update(params, "discount_rate", nil, fn
      percent when is_binary(percent) ->
        case Decimal.parse(String.trim(percent)) do
          {decimal, ""} -> Decimal.div(decimal, 100)
          _ -> percent
        end

      rate ->
        rate
    end)
  end

  defp rate_to_percent(%Decimal{} = rate),
    do: rate |> Decimal.mult(100) |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp rate_to_percent(value), do: value

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
         |> put_flash(:info, ~t"Promotion saved")
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
         |> put_flash(:info, ~t"Promotion deleted")
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
            <button
              type="button"
              phx-click="delete"
              data-confirm={~t"Delete this promotion? This can't be undone."}
              class="btn btn-ghost btn-sm text-error"
            >
              <.icon name="hero-trash" class="h-4 w-4" />
              {~t"Delete"}
            </button>
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
                <button
                  type="button"
                  phx-click="generate_code"
                  class="btn btn-ghost btn-sm btn-square mt-7"
                  title={~t"Generate code"}
                  aria-label={~t"Generate code"}
                >
                  <.icon name="hero-arrow-path" class="h-4 w-4" />
                </button>
                <button
                  type="button"
                  phx-click={JS.dispatch("edenflowers:copy", to: "##{@form[:code].id}")}
                  class="btn btn-ghost btn-sm btn-square mt-7"
                  title={~t"Copy code"}
                  aria-label={~t"Copy code"}
                >
                  <.icon name="hero-clipboard" class="h-4 w-4" />
                </button>
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

          <.button type="submit" variant="primary">{~t"Save promotion"}</.button>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end
end
