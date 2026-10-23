defmodule EdenflowersWeb.Admin.OrderFormLive do
  @moduledoc """
  Where Jennie enters a custom order (`:new`), and edits any open order
  after it is placed (`:edit`), online or custom, paid or not.
  """
  use EdenflowersWeb, :live_view

  require Ash.Query
  require Logger

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.CardDrawer, only: [card_drawer: 1]

  alias Edenflowers.Accounts
  alias Edenflowers.Catalog
  alias Edenflowers.Catalog.ProductVariant
  alias Edenflowers.Catalog.ProductVariantSize
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Fulfillment.DeliveryError
  alias Edenflowers.Fulfillment.Fee
  alias Edenflowers.Orders
  alias Edenflowers.Orders.EnteredPrice
  alias Edenflowers.Orders.LineItem
  alias Edenflowers.Orders.Order
  alias Edenflowers.Pricing
  alias Edenflowers.Translations
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case load(params, actor) do
      {:ok, mode, order} ->
        tax_rates = tax_rates(order, actor)

        {:ok,
         socket
         |> assign(:mode, mode)
         |> assign(:order, order)
         |> assign(:page_title, page_title(mode, order))
         |> assign(:locale, Localize.get_locale())
         |> assign(:fulfillment_options, Fulfillment.list_options!(actor: actor) |> Translations.translate())
         |> assign(:shop_calendar, Fulfillment.get_shop_calendar!(actor: actor))
         |> assign(:variant_options, variant_options(actor))
         |> assign(
           :card_variants,
           Catalog.list_card_drawer_variants!(actor: actor) |> Translations.translate_assoc(:product)
         )
         |> assign(:card_variant_id, order && Enum.find_value(order.line_items, &(&1.is_card && &1.product_variant_id)))
         |> assign(:tax_rates, tax_rates)
         |> assign(:default_tax_rate_id, default_tax_rate_id(tax_rates))
         |> assign(:form, build_form(mode, order, actor, tax_rates))
         |> assign(:customer_search_empty?, false)
         |> assign(:delivery_quote, stored_quote(mode, order))
         |> assign_date_warning()}

      {:error, message} ->
        {:ok,
         socket
         |> put_flash(:error, message)
         |> push_navigate(to: back_path(params))}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:method, selected_method(assigns.form, assigns.fulfillment_options, assigns.order))
      |> assign(:gift?, assigns.form[:gift].value in [true, "true"])
      |> assign(:time_choice, to_string(assigns.form[:fulfillment_time].value || "any"))
      |> assign(:card, chosen_card(assigns.card_variants, assigns.order, assigns.card_variant_id))

    quote = current_quote(assigns.delivery_quote, assigns.form, current_option_id(assigns))
    # Priced on render, so it follows every change to the form, the card and the quote.
    price = EnteredPrice.calculate(assigns.order, price_params(assigns), ok_quote(quote))

    assigns =
      assigns
      |> assign(:price, price)
      |> assign(:quote, charge(quote, price.free_delivery?))

    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.admin_page_header
          title={@page_title}
          back={order_form_back(@order)}
          sticky
        >
          <:subtitle :if={@order && @order.payment_status == :paid}>
            {~t"This order is paid. If the total changes, the order page shows the balance to collect or refund."}
          </:subtitle>
          <:actions>
            <.button type="submit" form="order-form" variant="primary" size="sm">
              {if @mode == :new, do: ~t"Place order", else: ~t"Save"}
            </.button>
          </:actions>
        </.admin_page_header>

        <.form
          for={@form}
          id="order-form"
          data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
          phx-change="validate"
          phx-auto-recover="recover"
          phx-submit="save"
          class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start"
        >
          <div class="space-y-6">
            <.form_section title={~t"Customer"}>
              <div :if={@mode == :new} class="mb-4">
                <label for="form_customer_id_text_input" class="mb-1 block">{~t"Find an existing customer"}</label>
                <LiveSelect.live_select
                  field={@form[:customer_id]}
                  id="customer-select"
                  allow_clear
                  debounce={300}
                  update_min_len={0}
                  style={:daisyui}
                  container_class="relative"
                  dropdown_class="absolute z-10 mt-2 max-h-64 w-full overflow-y-auto menu bg-base-100 border-base-content/12 border p-1 shadow"
                  option_class="break-words whitespace-normal pointer-coarse:min-h-11"
                  active_option_class="bg-primary text-primary-content"
                  available_option_class="cursor-pointer"
                  selected_option_class="cursor-pointer font-semibold"
                  text_input_class="input w-full pr-10 placeholder:text-base-content/75"
                  text_input_selected_class=""
                  no_basic_styles_for_clear_buttons
                  clear_button_class="btn btn-ghost btn-square absolute inset-y-0 right-0 h-full"
                >
                  <:option :let={option}>
                    <span data-selected={to_string(option.selected)}>{option.label}</span>
                  </:option>
                  <:clear_button>
                    <.icon name="hero-x-mark" class="size-5" />
                    <span class="sr-only">{~t"Clear customer selection"}</span>
                  </:clear_button>
                </LiveSelect.live_select>
                <p id="customer-search-help" class="text-base-content/75 mt-1.5 text-sm">
                  {~t"Search by name or email."}
                </p>
                <div id="customer-results" role="status">
                  <p :if={@customer_search_empty?} class="text-base-content/75 mt-2 text-sm">
                    {~t"No customers found."}
                  </p>
                </div>
              </div>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div class="sm:col-span-2">
                  <.input
                    field={@form[:customer_name]}
                    type="text"
                    label={~t"Name"}
                    class="input w-full"
                    autocapitalize="words"
                  />
                </div>
                <.input
                  field={@form[:customer_phone_number]}
                  type="tel"
                  label={~t"Phone"}
                  class="input w-full"
                  autocomplete="off"
                />
                <.input
                  field={@form[:customer_email]}
                  type="email"
                  label={~t"Email"}
                  class="input w-full"
                  autocomplete="off"
                />
                <.input
                  field={@form[:customer_instagram]}
                  type="text"
                  label={~t"Instagram"}
                  help={
                    ~t"A phone, an email or an Instagram handle is needed. With an email, the order shows in their account."
                  }
                  class="input w-full"
                  autocomplete="off"
                  autocapitalize="none"
                >
                  <:leading>@</:leading>
                </.input>
                <.input
                  field={@form[:locale]}
                  type="select"
                  label={~t"Language"}
                  help={~t"Used for their emails and the payment page."}
                  options={locale_options()}
                  class="select w-full"
                />
              </div>
            </.form_section>

            <.form_section title={~t"Items"}>
              <div id="order-lines" class="space-y-3">
                <.inputs_for :let={line} field={@form[:line_items]}>
                  <.order_line
                    line={line}
                    variant_options={@variant_options}
                    tax_rate_options={tax_rate_options(@tax_rates)}
                  />
                </.inputs_for>
                <p :if={@form[:line_items].value in [nil, []]} class="text-base-content/75 text-sm">
                  {~t"No items yet."}
                </p>
              </div>
              <div :if={@form.source.submitted_once?}>
                <.error :for={error <- @form[:line_items].errors}>{translate_error(error)}</.error>
              </div>
              <div class="mt-4 flex flex-wrap gap-2">
                <.button type="button" phx-click="add_line" phx-value-kind="catalogue" variant="secondary" size="sm">
                  <.icon name="hero-plus" class="h-4 w-4" /> {~t"Catalogue item"}
                </.button>
                <.button type="button" phx-click="add_line" phx-value-kind="custom" variant="secondary" size="sm">
                  <.icon name="hero-plus" class="h-4 w-4" /> {~t"Item with your own price"}
                </.button>
              </div>
            </.form_section>

            <.form_section title={~t"Delivery or pickup"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input
                  field={@form[:fulfillment_option_id]}
                  type="select"
                  label={~t"Method"}
                  prompt={~t"Choose…"}
                  options={Enum.map(@fulfillment_options, &{&1.name, &1.id})}
                  class="select w-full"
                />
                <div>
                  <.input field={@form[:fulfillment_date]} type="date" label={~t"Date"} class="input w-full" />
                  <div role="status">
                    <p
                      :if={@date_warning}
                      id="date-warning"
                      class="text-warning-content bg-warning/15 mt-2 px-3 py-2 text-sm"
                    >
                      {@date_warning}
                    </p>
                  </div>
                </div>
                <div class="sm:col-span-2">
                  <.input
                    :let={option}
                    field={@form[:fulfillment_time]}
                    type="radio-card"
                    label={~t"Time"}
                    options={fulfillment_time_options()}
                  >
                    {option.name}
                  </.input>
                  <div :if={@time_choice != "any"} class="mt-3 grid grid-cols-2 gap-4 sm:max-w-sm">
                    <.input
                      field={@form[:fulfillment_time_start]}
                      type="time"
                      label={if @time_choice == "at", do: ~t"At", else: ~t"From"}
                      class="input w-full"
                    />
                    <.input
                      :if={@time_choice == "between"}
                      field={@form[:fulfillment_time_end]}
                      type="time"
                      label={~t"To"}
                      class="input w-full"
                    />
                  </div>
                </div>
                <div :if={@method == :delivery} class="sm:col-span-2">
                  <.input
                    field={@form[:delivery_address]}
                    type="text"
                    label={~t"Delivery address"}
                    class="input w-full"
                    autocomplete="off"
                    phx-blur="quote_delivery"
                    loading={match?(%{status: :loading}, @quote)}
                    confirmed={match?(%{status: :ok}, @quote)}
                  />
                  <.delivery_quote quote={@quote} override={@form[:fulfillment_fee_override].value} />
                </div>
                <div :if={@method == :delivery} class="sm:col-span-2">
                  <.input
                    field={@form[:delivery_instructions]}
                    type="text"
                    label={~t"Delivery instructions"}
                    class="input w-full"
                  />
                </div>
                <.input
                  field={@form[:fulfillment_fee_override]}
                  type="text"
                  inputmode="decimal"
                  label={if @method == :delivery, do: ~t"Your own delivery fee", else: ~t"Your own fee"}
                  help={~t"Leave blank to calculate it as checkout would. 0 for free."}
                  class="input w-full"
                />
              </div>
            </.form_section>

            <.form_section title={~t"Who it's for"}>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div class="sm:col-span-2">
                  <.input
                    :let={option}
                    field={@form[:gift]}
                    type="radio-card"
                    label={~t"Recipient"}
                    options={[%{name: ~t"The customer", value: "false"}, %{name: ~t"Somebody else", value: "true"}]}
                  >
                    {option.name}
                  </.input>
                </div>
                <.input
                  :if={@gift?}
                  field={@form[:recipient_name]}
                  type="text"
                  label={~t"Recipient name"}
                  class="input w-full"
                  autocapitalize="words"
                />
                <%!-- An online order keeps the buyer's own number here when it isn't a gift. --%>
                <.input
                  :if={@gift? or (@order && @order.origin != :custom)}
                  field={@form[:recipient_phone_number]}
                  type="tel"
                  label={if @method == :delivery, do: ~t"Recipient phone (for the delivery)", else: ~t"Recipient phone"}
                  class="input w-full"
                  autocomplete="off"
                />
                <div :if={@gift?} class="sm:col-span-2" data-testid="order-card-choice">
                  <input type="hidden" name={@form[:card_variant_id].name} value={@card && @card.variant_id} />
                  <span class="mb-1 block">{~t"Card"}</span>
                  <div :if={@card} class="flex items-center gap-3">
                    <.image
                      src={@card.image_slug}
                      alt=""
                      width={64}
                      height={64}
                      sizes="64px"
                      class="h-16 w-16 shrink-0 object-cover"
                    />
                    <div class="min-w-0 flex-1">
                      <p class="font-medium">{@card.name}</p>
                      <p class="text-base-content/75 text-sm">{variant_size_label(@card.size)}</p>
                    </div>
                    <.button
                      type="button"
                      phx-click={JS.exec("phx-show", to: "#card-drawer")}
                      aria-haspopup="dialog"
                      variant="secondary"
                      size="sm"
                    >
                      {~t"Change"}
                    </.button>
                    <.button type="button" phx-click="remove_card" variant="secondary" size="sm">
                      {~t"Remove"}
                    </.button>
                  </div>
                  <.button
                    :if={is_nil(@card)}
                    type="button"
                    phx-click={JS.exec("phx-show", to: "#card-drawer")}
                    aria-haspopup="dialog"
                    variant="secondary"
                    size="sm"
                  >
                    <.icon name="hero-gift" class="h-4 w-4" /> {~t"Choose a card"}
                  </.button>
                  <p :if={is_nil(@card)} class="text-base-content/75 mt-1 text-sm">
                    {~t"Or none, if you write a card or ribbon of your own."}
                  </p>
                </div>
                <div :if={@gift?} id="card-message-field" class="sm:col-span-2">
                  <.input
                    field={@form[:card_message]}
                    type="textarea"
                    label={~t"Card message"}
                    rows="3"
                    maxlength={card_message_max(@card)}
                    class="textarea w-full"
                  />
                  <p class="text-base-content/75 mt-1 text-right text-sm tabular-nums">
                    <.character_count id="char-count" textarea={@form[:card_message].id} />/{card_message_max(@card)}
                  </p>
                </div>
              </div>
            </.form_section>
          </div>

          <aside class="flex flex-col gap-6 xl:row-span-2">
            <.form_section title={~t"Florist note"}>
              <:description>{~t"Only you see this."}</:description>
              <.input
                field={@form[:florist_note]}
                type="textarea"
                rows="4"
                aria-label={~t"Florist note"}
                class="textarea w-full"
              />
            </.form_section>
          </aside>

          <%!-- After the aside, so price and payment follow the florist note once stacked. --%>
          <.form_section title={~t"Price"} class="xl:col-start-1">
            <.price_summary price={@price} order={@order} method={@method} locale={@locale} />
          </.form_section>

          <.form_section :if={@mode == :new} title={~t"Payment"} class="xl:col-start-1">
            <div class="space-y-4">
              <.input :let={option} field={@form[:payment_terms]} type="radio-card" options={payment_options()}>
                {option.name}
              </.input>
              <.customer_email
                id="order-details-email"
                send={@form[:email_customer?]}
                label={~t"Email the order details to the customer (needs an email)"}
                message={@form[:message]}
              />
            </div>
          </.form_section>
        </.form>
      </.admin_page>

      <.card_drawer variants={@card_variants} locale={@locale} selected_variant_id={@card && @card.variant_id} />
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event(
        "live_select_change",
        %{"id" => "customer-select", "text" => term},
        %{assigns: %{mode: :new}} = socket
      ) do
    term = String.trim(term)

    customers =
      if term == "",
        do: [],
        else: Accounts.search_customers!(term, actor: socket.assigns.current_user, query: [limit: 10])

    options =
      Enum.map(customers, fn customer ->
        {Enum.join(Enum.reject([customer.name, to_string(customer.email)], &is_nil/1), " · "), customer.id}
      end)

    send_update(LiveSelect.Component, id: "customer-select", options: options)
    {:noreply, assign(socket, :customer_search_empty?, term != "" && customers == [])}
  end

  def handle_event("validate", %{"form" => params}, socket) do
    params = prefill_customer(params, socket.assigns)
    validate_form(socket, params)
  end

  def handle_event("recover", %{"form" => params}, socket) do
    validate_form(socket, params)
  end

  def handle_event("quote_delivery", %{"value" => address}, socket) do
    {:noreply, quote_delivery(socket, address, current_option_id(socket.assigns))}
  end

  def handle_event("add_line", %{"kind" => "catalogue"}, socket) do
    {:noreply, add_line(socket, %{"kind" => "catalogue", "quantity" => "1"})}
  end

  def handle_event("add_line", %{"kind" => "custom"}, socket) do
    {:noreply,
     add_line(socket, %{"kind" => "custom", "quantity" => "1", "tax_rate_id" => socket.assigns.default_tax_rate_id})}
  end

  def handle_event("remove_line", %{"path" => path}, socket) do
    {:noreply, update(socket, :form, &AshPhoenix.Form.remove_form(&1, path))}
  end

  def handle_event("select_card", %{"variant-id" => variant_id}, socket) do
    {:noreply, assign(socket, :card_variant_id, variant_id)}
  end

  def handle_event("remove_card", _params, socket) do
    {:noreply, assign(socket, :card_variant_id, nil)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(:info, saved_message(socket.assigns.mode))
         |> push_navigate(to: ~p"/admin/orders/#{order.id}")}

      {:error, form} ->
        if closed_meanwhile?(socket) do
          {:noreply,
           socket
           |> put_flash(
             :error,
             ~t"This order was cancelled or fulfilled while you were editing it, so it wasn't saved."
           )
           |> push_navigate(to: ~p"/admin/orders/#{socket.assigns.order.id}")}
        else
          {:noreply,
           socket
           |> assign(:form, form)
           |> put_flash(:error, ~t"The order wasn't saved. Check the fields marked below.")}
        end
    end
  end

  defp closed_meanwhile?(%{assigns: %{mode: :edit, order: order, current_user: actor}}) do
    Orders.get_order_for_admin!(order.id, actor: actor).fulfillment_status != :pending
  end

  defp closed_meanwhile?(_socket), do: false

  @impl true
  def handle_async(:delivery_quote, {:ok, {address, option_id, {:ok, %{error: nil} = result}}}, socket) do
    quote = %{
      status: :ok,
      address: address,
      option_id: option_id,
      geocoded_address: result.geocoded_address,
      fee: result.fulfillment_fee,
      in_free_delivery_zone: result.in_free_delivery_zone,
      distance: result.distance
    }

    {:noreply, assign(socket, :delivery_quote, quote)}
  end

  def handle_async(:delivery_quote, {:ok, {address, option_id, {:ok, %{error: reason}}}}, socket) do
    quote = %{status: :error, address: address, option_id: option_id, message: DeliveryError.message(reason)}
    {:noreply, assign(socket, :delivery_quote, quote)}
  end

  def handle_async(:delivery_quote, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:delivery_quote, result, socket) do
    Logger.error("Delivery quote failed: #{inspect(result)}")
    {address, option_id} = {socket.assigns.delivery_quote.address, socket.assigns.delivery_quote.option_id}
    quote = %{status: :error, address: address, option_id: option_id, message: DeliveryError.message(:unknown)}
    {:noreply, assign(socket, :delivery_quote, quote)}
  end

  defp load(%{"id" => id}, actor) do
    case Orders.get_order_for_admin(id, actor: actor, load: [:free_delivery?, line_items: [:subtotal]]) do
      {:ok, %Order{} = order} -> edit_mode(order)
      _ -> {:error, ~t"Order not found."}
    end
  end

  defp load(_params, _actor), do: {:ok, :new, nil}

  defp edit_mode(%{fulfillment_status: status}) when status != :pending,
    do: {:error, ~t"This order is no longer open, so it can't be changed."}

  defp edit_mode(order), do: {:ok, :edit, order}

  defp page_title(:new, _order), do: ~t"New custom order"
  defp page_title(_mode, order), do: ~t"Edit order #{reference = order.order_reference}"

  defp order_form_back(nil), do: {~t"Orders", ~p"/admin/orders"}
  defp order_form_back(order), do: {order.customer_name || order.order_reference, ~p"/admin/orders/#{order.id}"}

  defp back_path(%{"id" => id}), do: ~p"/admin/orders/#{id}"
  defp back_path(_params), do: ~p"/admin/orders"

  defp build_form(:new, _order, actor, _tax_rates) do
    Order
    |> AshPhoenix.Form.for_create(:place_custom,
      actor: actor,
      params: %{
        "locale" => "sv-FI",
        "gift" => "false",
        "fulfillment_time" => "any",
        "payment_terms" => "payment_link",
        "email_customer?" => "true"
      },
      transform_params: &transform_params/3,
      forms: [line_items: [type: :list, resource: LineItem, create_action: :enter]]
    )
    |> to_form()
  end

  # A catalogue line the order has is kept by id, so it keeps the price it was
  # sold at. A line Jennie priced herself carries its price in the form, so it
  # is entered afresh.
  defp build_form(:edit, order, actor, tax_rates) do
    {catalogue, custom} =
      order.line_items
      |> Enum.reject(& &1.is_card)
      |> Enum.split_with(& &1.product_variant_id)

    form =
      AshPhoenix.Form.for_update(order, :edit,
        actor: actor,
        params: %{"fulfillment_time" => time_choice(order)},
        transform_params: &transform_params/3,
        forms: [
          line_items: [
            type: :list,
            resource: LineItem,
            create_action: :enter,
            update_action: :set_quantity,
            data: catalogue
          ]
        ]
      )

    custom
    |> Enum.reduce(form, fn line_item, form ->
      AshPhoenix.Form.add_form(form, :line_items,
        params: %{
          "kind" => "custom",
          "product_name" => line_item.product_name,
          "unit_price" => Decimal.to_string(line_item.unit_price, :normal),
          "tax_rate_id" => tax_rate_id_for(tax_rates, line_item.tax_rate),
          "quantity" => to_string(line_item.quantity)
        }
      )
    end)
    |> to_form()
  end

  defp transform_params(_form, params, _action) do
    Map.update(params, "fulfillment_fee_override", nil, &decimal_comma/1)
  end

  defp decimal_comma(value) when is_binary(value), do: String.replace(value, ",", ".")
  defp decimal_comma(value), do: value

  defp add_line(socket, params) do
    update(socket, :form, &AshPhoenix.Form.add_form(&1, :line_items, params: params))
  end

  defp existing_line_name(%{variant_size: nil} = line_item), do: line_item.product_name

  defp existing_line_name(line_item),
    do: "#{line_item.product_name} · #{variant_size_label(line_item.variant_size)}"

  # A line stores the percentage it was charged, not the rate it came from.
  defp tax_rate_id_for(tax_rates, percentage) do
    Enum.find_value(tax_rates, fn rate -> Decimal.equal?(rate.percentage, percentage) && rate.id end)
  end

  defp default_tax_rate_id([]), do: nil
  defp default_tax_rate_id([standard | _]), do: standard.id

  defp tax_rates(nil, actor), do: Pricing.list_selectable_tax_rates!(actor: actor)

  defp tax_rates(order, actor) do
    percentages = for %{product_variant_id: nil, tax_rate: percentage} <- order.line_items, do: percentage
    Pricing.list_selectable_tax_rates!(%{percentages: percentages}, actor: actor)
  end

  # Cards are chosen as the order's card, not added as items.
  defp variant_options(actor) do
    ProductVariant
    |> Ash.Query.filter(product.product_category.slug != "cards")
    |> Ash.Query.load(:product)
    |> Ash.read!(actor: actor)
    |> Enum.sort_by(&{&1.product.name, &1.price})
    |> Enum.map(fn variant ->
      {"#{variant.product.name} · #{variant_size_label(variant.size)} · #{Format.currency(variant.price, Format.locale())}",
       variant.id}
    end)
  end

  # A card the drawer no longer offers, as it has sold out since, is still the order's own.
  defp chosen_card(_card_variants, _order, nil), do: nil

  defp chosen_card(card_variants, order, variant_id) do
    case Enum.find(card_variants, &(&1.id == variant_id)) do
      nil ->
        line_item = Enum.find(order.line_items, &(&1.is_card && &1.product_variant_id == variant_id))

        %{
          variant_id: variant_id,
          name: line_item.product_name,
          image_slug: line_item.product_image_slug,
          size: line_item.variant_size
        }

      variant ->
        %{variant_id: variant.id, name: variant.product.name, image_slug: variant.photo_slug, size: variant.size}
    end
  end

  defp card_message_max(%{size: size}) when not is_nil(size), do: ProductVariantSize.max_message_length(size)
  defp card_message_max(_card), do: ProductVariantSize.max_message_length(:large)

  defp last_order_with_phone(customer_id, actor),
    do: Orders.get_last_order_with_customer_phone!(customer_id, actor: actor, not_found_error?: false)

  defp prefill_customer(%{"customer_id" => id} = params, %{mode: :new} = assigns)
       when id not in [nil, ""] do
    if id == assigns.form[:customer_id].value do
      params
    else
      case Accounts.get_customer_for_admin(id, actor: assigns.current_user) do
        {:ok, customer} when not is_nil(customer) ->
          last = last_order_with_phone(customer.id, assigns.current_user)

          Map.merge(params, %{
            "customer_name" => customer.name || "",
            "customer_email" => to_string(customer.email),
            "customer_phone_number" => last_phone_number(last),
            # Only a newsletter signup saves a customer's language, so most have
            # just the one their last order was placed in.
            "locale" => customer.locale || last_locale(last) || params["locale"]
          })

        _ ->
          params
      end
    end
  end

  defp prefill_customer(params, _assigns), do: params

  defp last_phone_number(nil), do: ""
  defp last_phone_number(order), do: order.customer_phone_number || order.recipient_phone_number || ""

  defp last_locale(nil), do: nil
  defp last_locale(order), do: order.locale

  defp validate_form(socket, params) do
    option_before = current_option_id(socket.assigns)

    socket =
      socket
      |> assign(:form, AshPhoenix.Form.validate(socket.assigns.form, params))
      |> assign_date_warning()

    if current_option_id(socket.assigns) == option_before do
      {:noreply, socket}
    else
      {:noreply, requote_for_new_option(socket)}
    end
  end

  # Priced as soon as the address is typed, so Jennie can tell a caller what
  # delivery costs. Saving prices it again: this quote is only for her to read.
  defp quote_delivery(socket, address, option_id) do
    address = String.trim(address || "")

    cond do
      address == "" or is_nil(option_id) ->
        assign(socket, :delivery_quote, nil)

      quoted?(socket.assigns.delivery_quote, address, option_id) ->
        socket

      true ->
        # A newer lookup with the same name cancels one still in flight.
        socket
        |> assign(:delivery_quote, %{status: :loading, address: address, option_id: option_id})
        |> start_async(:delivery_quote, fn ->
          {address, option_id, Fulfillment.calculate_delivery(address, option_id, authorize?: false)}
        end)
    end
  end

  defp requote_for_new_option(socket) do
    if selected_method(socket.assigns.form, socket.assigns.fulfillment_options, socket.assigns.order) == :delivery do
      quote_delivery(socket, socket.assigns.form[:delivery_address].value, current_option_id(socket.assigns))
    else
      assign(socket, :delivery_quote, nil)
    end
  end

  defp quoted?(%{address: address, option_id: option_id}, address, option_id), do: true
  defp quoted?(_quote, _address, _option_id), do: false

  defp current_option_id(%{form: form, order: order}) do
    form[:fulfillment_option_id].value || (order && order.fulfillment_option_id)
  end

  # An order already priced by distance can be quoted again without geocoding.
  defp stored_quote(:edit, %{fulfillment_method: :delivery, distance: distance} = order)
       when is_integer(distance) do
    case Fulfillment.get_option_by_id(order.fulfillment_option_id, authorize?: false) do
      {:ok, option} ->
        case Fee.calculate(option, distance) do
          %{error: nil} = fee ->
            %{
              status: :ok,
              address: order.delivery_address,
              option_id: option.id,
              geocoded_address: order.geocoded_address,
              fee: fee.fulfillment_fee,
              in_free_delivery_zone: fee.in_free_delivery_zone,
              distance: distance
            }

          _out_of_range ->
            nil
        end

      _ ->
        nil
    end
  end

  defp stored_quote(_mode, _order), do: nil

  defp charge(%{status: :ok} = quote, free_delivery?) do
    %{quote | fee: Orders.charged_fulfillment_fee!(quote.fee, quote.in_free_delivery_zone, free_delivery?)}
  end

  defp charge(quote, _free_delivery?), do: quote

  defp ok_quote(%{status: :ok} = quote), do: %{fee: quote.fee, in_free_delivery_zone: quote.in_free_delivery_zone}
  defp ok_quote(_quote), do: nil

  defp price_params(assigns) do
    assigns.form
    |> AshPhoenix.Form.params()
    |> Map.put("card_variant_id", assigns.card && assigns.card.variant_id)
  end

  # A quote for an address or option no longer in the form says nothing.
  defp current_quote(quote, form, option_id) do
    address = String.trim(form[:delivery_address].value || "")
    if quoted?(quote, address, option_id), do: quote
  end

  defp saved_message(:new), do: ~t"Order placed."
  defp saved_message(_mode), do: ~t"Order updated."

  # Jennie may book a closed day; she is told it is closed, not stopped.
  defp assign_date_warning(socket) do
    form = socket.assigns.form

    warning =
      with {:ok, date} <- parse_date(form[:fulfillment_date].value),
           reason when reason not in [nil, :past] <-
             Availability.unavailable_reason(socket.assigns.shop_calendar, date, Edenflowers.ShopTime.now()) do
        date_warning(reason)
      else
        _ -> nil
      end

    assign(socket, :date_warning, warning)
  end

  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp parse_date(_value), do: :error

  defp date_warning(:weekday_disabled), do: ~t"This weekday is normally closed. Booking it anyway."
  defp date_warning(:date_disabled), do: ~t"You've closed this date in the calendar. Booking it anyway."

  defp date_warning(:same_day_delivery_disabled), do: ~t"Same-day isn't normally offered. Booking it anyway."

  defp date_warning(:order_deadline_passed), do: ~t"Today's order deadline has passed. Booking it anyway."

  defp selected_method(form, fulfillment_options, order) do
    option_id = form[:fulfillment_option_id].value || (order && order.fulfillment_option_id)

    case Enum.find(fulfillment_options, &(&1.id == option_id)) do
      %{fulfillment_method: method} -> method
      nil -> order && order.fulfillment_method
    end
  end

  defp locale_options, do: [{"Svenska", "sv-FI"}, {"Suomi", "fi"}, {"English", "en-GB"}]

  defp time_choice(%{fulfillment_time_start: nil}), do: "any"
  defp time_choice(%{fulfillment_time_end: nil}), do: "at"
  defp time_choice(_order), do: "between"

  defp fulfillment_time_options do
    [%{name: ~t"Any time", value: "any"}, %{name: ~t"At", value: "at"}, %{name: ~t"Between", value: "between"}]
  end

  defp payment_options do
    [
      %{name: ~t"Payment link", value: "payment_link"},
      %{name: ~t"Invoice", value: "invoice"},
      %{name: ~t"In person", value: "on_fulfillment"}
    ]
  end

  defp tax_rate_options(tax_rates) do
    Enum.map(tax_rates, &{"#{&1.name} (#{Format.percentage(&1.percentage, Format.locale())})", &1.id})
  end

  attr :quote, :map, default: nil
  attr :override, :any, default: nil

  defp delivery_quote(assigns) do
    ~H"""
    <div aria-live="polite">
      <div :if={match?(%{status: :ok}, @quote)} id="delivery-quote" class="text-base-content/75 mt-1.5 text-sm">
        <p :if={@quote.geocoded_address}>{~t"Delivering to #{address = @quote.geocoded_address}"}</p>
        <p>
          {Format.currency(@quote.fee, Format.locale())} ({Format.distance(@quote.distance, Format.locale())})
          <span :if={@override not in [nil, ""]}>· {~t"your own fee replaces this"}</span>
        </p>
      </div>
      <p :if={match?(%{status: :error}, @quote)} id="delivery-quote" class="text-warning-content mt-1.5 text-sm">
        {@quote.message}. {~t"You can still set your own fee."}
      </p>
    </div>
    """
  end

  attr :line, Phoenix.HTML.Form, required: true
  attr :variant_options, :list, required: true
  attr :tax_rate_options, :list, required: true

  # A line the order already has: its product is fixed, only how many changes.
  defp order_line(%{line: %{source: %{type: :update}}} = assigns) do
    ~H"""
    <.line_row line={@line}>
      <div class="flex min-w-0 flex-1 basis-64 flex-col">
        <span class="mb-1">{~t"Product"}</span>
        <p class="flex h-10 items-center text-base font-medium">{existing_line_name(@line.data)}</p>
      </div>
      <div class="w-20">
        <.input field={@line[:quantity]} type="number" min="1" label={~t"Qty"} class="input w-full tabular-nums" />
      </div>
    </.line_row>
    """
  end

  defp order_line(%{line: %{params: %{"kind" => "catalogue"}}} = assigns) do
    ~H"""
    <.line_row line={@line}>
      <.input field={@line[:kind]} type="hidden" />
      <div class="min-w-0 flex-1 basis-64">
        <.input
          field={@line[:product_variant_id]}
          type="select"
          label={~t"Product"}
          prompt={~t"Choose…"}
          options={@variant_options}
          class="select w-full"
        />
      </div>
      <div class="w-20">
        <.input field={@line[:quantity]} type="number" min="1" label={~t"Qty"} class="input w-full tabular-nums" />
      </div>
    </.line_row>
    """
  end

  defp order_line(assigns) do
    ~H"""
    <.line_row line={@line}>
      <.input field={@line[:kind]} type="hidden" />
      <div class="min-w-0 flex-1 basis-full">
        <.input
          field={@line[:product_name]}
          type="text"
          label={~t"Description"}
          placeholder={~t"e.g. Funeral spray, white roses"}
          class="input w-full"
        />
      </div>
      <div class="w-32">
        <.input
          field={@line[:unit_price]}
          type="text"
          inputmode="decimal"
          label={~t"Price each (€)"}
          class="input w-full tabular-nums"
        />
      </div>
      <div class="min-w-0 flex-1 basis-40">
        <.input field={@line[:tax_rate_id]} type="select" label={~t"VAT"} options={@tax_rate_options} class="select w-full" />
      </div>
      <div class="w-20">
        <.input field={@line[:quantity]} type="number" min="1" label={~t"Qty"} class="input w-full tabular-nums" />
      </div>
    </.line_row>
    """
  end

  attr :line, Phoenix.HTML.Form, required: true
  slot :inner_block, required: true

  # Numbered, so Jennie can tell the rows apart.
  defp line_row(assigns) do
    ~H"""
    <fieldset class="border-base-content/12 border p-3" data-testid="order-line">
      <legend class="text-base-content/75 px-1 text-xs">{~t"Item #{number = @line.index + 1}"}</legend>
      <%!-- Top-aligned so an error under one field leaves the others in line. --%>
      <div class="flex flex-wrap items-start gap-3">
        {render_slot(@inner_block)}
        <.icon_button
          phx-click="remove_line"
          phx-value-path={@line.name}
          class="text-error size-10 mt-7"
          aria_label={~t"Remove item #{number = @line.index + 1}"}
        >
          <.icon name="hero-trash" class="h-4 w-4" />
        </.icon_button>
      </div>
    </fieldset>
    """
  end

  attr :price, :map, required: true
  attr :order, :map, default: nil
  attr :method, :atom, default: nil
  attr :locale, :string, required: true

  # What Jennie tells a customer on the phone, priced as saving will price it.
  defp price_summary(assigns) do
    assigns = assign(assigns, :paid, assigns.order && assigns.order.amount_paid)

    ~H"""
    <p :if={@price.lines == []} id="order-price" class="text-base-content/75 text-sm">
      {~t"Add an item to see the price."}
    </p>
    <dl :if={@price.lines != []} id="order-price" class="text-sm">
      <.money_row
        :for={line <- @price.lines}
        label={"#{line.quantity} × #{line.name}"}
        amount={line.total}
        locale={@locale}
      />
      <.money_row
        :if={@price.fulfillment_fee}
        label={if @method == :delivery, do: ~t"Delivery", else: ~t"Fulfillment fee"}
        amount={@price.fulfillment_fee}
        locale={@locale}
      />
      <div :if={is_nil(@price.fulfillment_fee)} class="text-base-content/75 py-0.5">
        {if @method == :delivery,
          do: ~t"Delivery is added once the address is priced.",
          else: ~t"The fee is added once you choose delivery or pickup."}
      </div>
      <.money_row strong label={~t"Total"} amount={@price.total} locale={@locale} />
      <.money_row muted label={~t"Includes VAT"} amount={@price.vat} locale={@locale} />
      <.money_row
        :if={@paid && Decimal.positive?(@paid)}
        ruled
        label={~t"Paid"}
        amount={Decimal.negate(@paid)}
        locale={@locale}
      />
      <.money_row
        :if={@paid && Decimal.positive?(@paid)}
        strong
        label={~t"Balance"}
        amount={Decimal.sub(@price.total, @paid)}
        locale={@locale}
      />
    </dl>
    """
  end
end
