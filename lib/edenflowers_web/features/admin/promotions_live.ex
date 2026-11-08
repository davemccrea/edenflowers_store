defmodule EdenflowersWeb.Admin.PromotionsLive do
  @moduledoc """
  Admin list of promotion codes and their use.
  """

  use EdenflowersWeb, {:live_view, gettext_domain: "admin"}
  use Cinder.UrlSync

  import EdenflowersWeb.Admin.Components

  alias Edenflowers.Format
  alias Edenflowers.Pricing
  alias Edenflowers.Pricing.Promotion
  alias EdenflowersWeb.Admin.DefaultTableView
  alias EdenflowersWeb.Admin.PromotionFormLive
  alias EdenflowersWeb.Layouts

  # Hand-made promotions; newsletter and card codes would otherwise bury them.
  @default_view %{"kind" => "manual"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, ~t"Promotions")
     |> assign(:locale, Localize.get_locale())
     |> assign_welcome_offer_form()}
  end

  @impl true
  def handle_params(params, uri, socket) do
    {:noreply, DefaultTableView.handle_params(params, uri, socket, @default_view)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header title={~t"Promotions"}>
          <:actions>
            <.button navigate={~p"/admin/promotions/new"} variant="primary" size="sm">
              <.icon name="hero-plus" class="h-4 w-4" />
              {~t"New promotion"}
            </.button>
          </:actions>
        </.admin_page_header>

        <.form_section title={~t"Welcome offer"} class="mb-6">
          <:description>
            {~t"Codes already sent keep their rate."}
          </:description>
          <.form
            for={@welcome_offer_form}
            id="welcome-offer-form"
            phx-change="validate_welcome_offer"
            phx-submit="save_welcome_offer"
            class="flex items-end gap-3"
          >
            <.input
              field={@welcome_offer_form[:discount_rate]}
              value={PromotionFormLive.rate_to_percent(@welcome_offer_form[:discount_rate].value)}
              type="text"
              inputmode="decimal"
              label={~t"Discount (%)"}
              class="input w-28 tabular-nums"
            />
            <.button type="submit" variant="primary">{~t"Save"}</.button>
          </.form>
        </.form_section>

        <Cinder.collection
          id="promotions-table"
          resource={Promotion}
          actor={@current_user}
          query_opts={[load: [:usage]]}
          search={[
            label: ~t"Search",
            placeholder: ~t"Search name or code…",
            fn: &search_promotions/3
          ]}
          url_state={@url_state}
          sort_mode="exclusive"
          page_size={[default: 25, options: [10, 25, 50, 100]]}
          theme={EdenflowersWeb.Admin.CinderTheme}
          click={fn promotion -> JS.navigate(~p"/admin/promotions/#{promotion.id}") end}
        >
          <:filter
            field="kind"
            label={~t"Source"}
            type={:select}
            prompt={~t"All"}
            options={[
              {kind_label(:manual), :manual},
              {kind_label(:pass_it_on), :pass_it_on},
              {kind_label(:newsletter), :newsletter}
            ]}
          />
          <:col :let={promotion} field="name" search sort={[cycle: [:asc, :desc]]} label={~t"Name"}>
            <.link
              navigate={~p"/admin/promotions/#{promotion.id}"}
              class="max-w-28 inline-block truncate align-middle font-semibold hover:underline sm:max-w-none"
            >
              {promotion.name}
            </.link>
          </:col>
          <:col :let={promotion} field="code" search sort label={~t"Code"}>
            <span class="inline-flex items-center gap-1">
              <span id={"promotion-code-#{promotion.id}"} class="font-mono">{promotion.code}</span>
              <.copy_button
                id={"copy-promotion-code-#{promotion.id}"}
                target={"#promotion-code-#{promotion.id}"}
                label={~t"Copy code"}
                size="xs"
              />
            </span>
          </:col>
          <:col :let={promotion} field="discount_rate" sort label={~t"Discount"} class="text-right">
            <span class="tabular-nums">{Format.percentage(promotion.discount_rate, @locale)}</span>
          </:col>
          <:col :let={promotion} field="minimum_cart_total" sort label={~t"Minimum"} class="text-right max-sm:hidden">
            <span class="whitespace-nowrap tabular-nums">{Format.currency(promotion.minimum_cart_total, @locale)}</span>
          </:col>
          <:col
            :let={promotion}
            field="start_date"
            sort={[cycle: [nil, :desc, :asc]]}
            label={~t"Starts"}
            class="max-sm:hidden"
          >
            <span :if={promotion.start_date} class="whitespace-nowrap tabular-nums">
              {Format.date(promotion.start_date, @locale)}
            </span>
            <.blank :if={is_nil(promotion.start_date)} />
          </:col>
          <:col
            :let={promotion}
            field="expiration_date"
            sort={[cycle: [nil, :desc, :asc]]}
            label={~t"Expires"}
            class="max-sm:hidden"
          >
            <span :if={promotion.expiration_date} class="whitespace-nowrap tabular-nums">
              {Format.date(promotion.expiration_date, @locale)}
            </span>
            <.blank :if={is_nil(promotion.expiration_date)} />
          </:col>
          <:col :let={promotion} field="kind" label={~t"Source"} class="max-xl:hidden">
            <span class="whitespace-nowrap">{kind_label(promotion.kind)}</span>
          </:col>
          <:col :let={promotion} field="usage" sort label={~t"Used"} class="text-right max-sm:hidden">
            <span class="tabular-nums">{usage_label(promotion)}</span>
          </:col>
        </Cinder.collection>
      </.admin_page>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("validate_welcome_offer", %{"form" => params}, socket) do
    {:noreply, assign(socket, :welcome_offer_form, AshPhoenix.Form.validate(socket.assigns.welcome_offer_form, params))}
  end

  def handle_event("save_welcome_offer", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.welcome_offer_form, params: params) do
      {:ok, _offer} ->
        {:noreply,
         socket
         |> assign_welcome_offer_form()
         |> put_flash(:success, ~t"Welcome offer saved.")}

      {:error, form} ->
        {:noreply, assign(socket, :welcome_offer_form, form)}
    end
  end

  defp assign_welcome_offer_form(socket) do
    actor = socket.assigns.current_user

    form =
      Pricing.get_welcome_offer!(actor: actor)
      |> AshPhoenix.Form.for_update(:update, actor: actor, transform_params: &PromotionFormLive.percent_to_rate/3)

    assign(socket, :welcome_offer_form, to_form(form))
  end

  def default_path, do: ~p"/admin/promotions?#{@default_view}"

  defp kind_label(:manual), do: ~t"Created by you"
  defp kind_label(:pass_it_on), do: ~t"Pass-it-on cards"
  defp kind_label(:newsletter), do: ~t"Newsletter"

  defp usage_label(%{usage_limit: nil, usage: usage}), do: to_string(usage)
  defp usage_label(%{usage_limit: limit, usage: usage}), do: "#{usage} / #{limit}"

  defp search_promotions(query, _searchable_columns, search_term) do
    require Ash.Query
    term = Ash.CiString.new(search_term)
    Ash.Query.filter(query, matches?(term: ^term))
  end
end
