defmodule EdenflowersWeb.Checkout.CheckoutLive do
  use EdenflowersWeb, :live_view

  require Logger

  import EdenflowersWeb.Checkout.Fields, only: [steps: 1]
  import EdenflowersWeb.CardDrawer, only: [card_drawer: 1]
  import EdenflowersWeb.StoreCalendar, only: [store_calendar: 1]

  alias Edenflowers.Catalog.ProductVariantSize

  alias Edenflowers.Orders
  alias Edenflowers.Payments

  alias Edenflowers.Fulfillment

  alias Edenflowers.Catalog
  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Fulfillment.Fee
  alias Edenflowers.Orders.Calculations.Vat
  alias Edenflowers.Orders.Order
  alias Edenflowers.Orders.Validations.WithinStock
  alias Edenflowers.PhoneNumber
  alias Edenflowers.Translations

  @checkout_states Order.checkout_states()

  @return_to %{
    contact_details: &Orders.return_to_contact_details!/2,
    gift_options: &Orders.return_to_gift_options!/2,
    delivery: &Orders.return_to_delivery!/2
  }

  # A cart change after "pay" has updated the PaymentIntent would charge the
  # old amount, so anything that changes the total is inert from the click
  # until Stripe settles.
  @locked_while_paying "#cart-drawer, [data-locked-while-paying]"

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(_params, _session, %{assigns: %{order: order}} = socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "line_item:changed:#{order.id}")
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:checkout_restarted:#{order.id}")
    end

    with :ok <- validate_cart_not_empty(order),
         :ok <- validate_not_add_ons_only(order),
         {:ok, fulfillment_options} <- Fulfillment.list_options_for_checkout() do
      order = ensure_fulfillment_default(order, fulfillment_options, socket.assigns[:current_user])
      fulfillment_options = Translations.translate(fulfillment_options)
      card_variants = Catalog.list_card_drawer_variants!() |> Translations.translate_assoc(:product)

      {:ok,
       socket
       |> assign(:current_user, load_newsletter_offer_hidden(socket.assigns[:current_user]))
       |> assign(:id, "checkout")
       |> assign(:page_title, ~t"Checkout")
       |> assign(:fulfillment_options, fulfillment_options)
       |> assign(:shop_calendar, Fulfillment.get_shop_calendar!())
       |> assign(:card_variants, card_variants)
       |> assign(:order, order)
       |> assign(:delivery_quote, quote_from_order(order))
       |> assign(:form, build_submit_form(order, prefill_contact_details(order, socket.assigns[:current_user])))
       |> assign(:client_secret, nil)
       |> assign(:customer_session_client_secret, nil)
       |> maybe_setup_payment(order, actor(socket))
       |> maybe_scroll_to_current_step()}
    else
      {:error, :empty_cart} ->
        # Reset so a stale step or details don't survive into the next checkout.
        Orders.restart_checkout!(order, actor: socket.assigns[:current_user])
        handle_mount_error(socket, "Cart is empty", ~t"Cart is empty")

      {:error, :add_ons_only} ->
        {:ok, back_to_store(socket)}

      error ->
        Logger.error("Error loading checkout: #{inspect(error)}")
        handle_mount_error(socket, "Error loading checkout", ~t"Error loading checkout")
    end
  end

  # The step is mirrored in the URL so the browser's back button steps back
  # through checkout. The order's state still decides which step shows: a URL
  # step before it steps the order back, and any other is corrected in place,
  # as only Next moves the order forward.
  #
  # So browser forward after going back lands on the earlier step, with the
  # customer's details still filled in for Next. Going back moves the order's
  # state, and forward would have to submit the step again or work the step
  # out from the order's data instead of storing it (TASK-24). Forward is
  # rarely used, so neither was worth it.
  @impl true
  def handle_params(params, _uri, %{assigns: %{fulfillment_options: _}} = socket) do
    order = socket.assigns.order
    step = Enum.find(@checkout_states, &(Atom.to_string(&1) == params["step"]))

    cond do
      order.state not in @checkout_states or step == order.state ->
        {:noreply, socket}

      step && step_index(step) < step_index(order.state) ->
        Map.fetch!(@return_to, step).(order, actor: actor(socket))

        {:noreply,
         socket
         |> reload_order()
         |> push_event("focus-element", %{id: section_id(socket.assigns.id, step)})}

      true ->
        {:noreply, correct_step_url(socket)}
    end
  end

  # Mount navigated away.
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-[58rem] mx-auto w-full">
          <h1 class="page-title mb-10 md:mb-12">{~t"Checkout"}</h1>
        </div>
        <div class="flex flex-col gap-12">
          <div class="max-w-[58rem] mx-auto flex w-full flex-col gap-12 md:flex-row md:gap-12 lg:gap-16">
            <div id={@id} class="md:max-w-lg md:flex-1" phx-hook="FocusElement">
              <%!-- Outer step chrome (titles, summaries, edit links) lives in Checkout.Fields.
                   The <section>s below are the inner content for the active step. --%>
              <.steps state={@order.state} order={@order}>
                <.checkout_step order={@order} id={@id} state={:contact_details} testid="checkout-step-1">
                  <.form
                    id={"#{@id}-form-1"}
                    for={@form}
                    phx-change="validate_form"
                    phx-submit="save_form"
                    class="flex flex-col space-y-6"
                    data-testid="checkout-form-1"
                  >
                    <.input
                      label={~t"Your name *"}
                      field={@form[:customer_name]}
                      type="text"
                      autocomplete="name"
                      aria-required="true"
                      data-testid="customer-name-input"
                    />
                    <.input
                      label={~t"Email *"}
                      field={@form[:customer_email]}
                      type="email"
                      autocomplete="email"
                      aria-required="true"
                      data-testid="customer-email-input"
                    />
                    <p
                      :if={@order.subscription? and is_nil(@current_user)}
                      class="text-base-content/70 -mt-4 text-sm"
                      data-testid="account-note"
                    >
                      {~t"We'll set up an account with this email so you can pause or cancel."}
                    </p>

                    <.input
                      :if={not @order.subscription? and !hide_newsletter_offer?(@order, @current_user)}
                      label={~t"Subscribe to the newsletter to receive 15% off your first order by email."}
                      field={@form[:newsletter_opt_in]}
                      type="checkbox"
                      class="checkbox checkbox-sm"
                      data-testid="newsletter-opt-in-checkbox"
                    />

                    <.form_button data-testid="step-1-next-button">{~t"Next"}</.form_button>
                  </.form>
                </.checkout_step>

                <.checkout_step order={@order} id={@id} state={:gift_options} testid="checkout-step-2">
                  <.form
                    id={"#{@id}-form-2"}
                    for={@form}
                    phx-change="validate_form"
                    phx-submit="save_form"
                    class="flex flex-col space-y-6"
                    data-testid="checkout-form-2"
                  >
                    <.input
                      :let={option}
                      type="radio-card"
                      label={~t"Recipient *"}
                      field={@form[:gift]}
                      options={[%{name: ~t"For me", value: "false"}, %{name: ~t"For somebody else", value: "true"}]}
                      phx-change="set_gift"
                      data-testid="gift-recipient-selector"
                    >
                      {option.name}
                    </.input>

                    <.input
                      hidden={not @order.gift}
                      label={~t"Recipient name *"}
                      field={@form[:recipient_name]}
                      type="text"
                      aria-required="true"
                      data-testid="recipient-name-input"
                    />

                    <.gift_card_slot order={@order} form={@form} id={@id} card_variants={@card_variants} />

                    <.form_button>{gettext("Next")}</.form_button>
                  </.form>
                </.checkout_step>

                <.checkout_step order={@order} id={@id} state={:delivery}>
                  <.form id={"#{@id}-form-3a"} for={%{}} phx-change="update_fulfillment_option">
                    <.input
                      :let={option}
                      type="radio-card"
                      field={@form[:fulfillment_option_id]}
                      options={
                        Enum.map(@fulfillment_options, fn %{id: id, name: name} ->
                          %{name: name, value: id}
                        end)
                      }
                      label={~t"Delivery method *"}
                    >
                      {option.name}
                    </.input>
                  </.form>

                  <%= if @order.fulfillment_option do %>
                    <.form
                      id={"#{@id}-form-3b"}
                      for={@form}
                      phx-change="validate_form"
                      phx-submit="save_form"
                      class="flex flex-col space-y-6"
                    >
                      <.live_component
                        :if={@order.fulfillment_method == :delivery}
                        id="address-input"
                        module={EdenflowersWeb.Checkout.AddressInput}
                        order={@order}
                        quote={@delivery_quote}
                        label={recipient_label(@order, :address)}
                        autocomplete={own_details_autocomplete(@order, "street-address")}
                      />

                      <.input
                        :if={@order.fulfillment_method == :delivery}
                        label={~t"Delivery instructions"}
                        field={@form[:delivery_instructions]}
                        type="text"
                        placeholder={~t"e.g. Door code 1234, leave at the front door"}
                      />

                      <.input
                        label={recipient_label(@order, :phone)}
                        help={phone_help(@order)}
                        placeholder="040 123 4567"
                        field={@form[:recipient_phone_number]}
                        value={typed_phone_number(@form)}
                        phx-blur="format_phone_number"
                        type="tel"
                        autocomplete={own_details_autocomplete(@order, "tel")}
                        aria-required="true"
                      />

                      <fieldset class="flex flex-col">
                        <legend class="mb-1">
                          <%= if @order.fulfillment_method == :delivery do %>
                            {~t"Delivery date *"}
                          <% else %>
                            {~t"Pickup date *"}
                          <% end %>
                        </legend>
                        <div class="sm:max-w-md">
                          <.store_calendar
                            id="calendar"
                            error={
                              Phoenix.Component.used_input?(@form[:fulfillment_date]) and
                                Enum.any?(@form[:fulfillment_date].errors)
                            }
                            selected_date={@form[:fulfillment_date].value}
                            calendar={@shop_calendar}
                          />
                        </div>
                        <.field_errors field={@form[:fulfillment_date]} />
                        <.input field={@form[:fulfillment_date]} hidden />
                      </fieldset>

                      <.form_button>{~t"Next"}</.form_button>
                    </.form>
                  <% end %>
                </.checkout_step>

                <.checkout_step order={@order} id={@id} state={:payment}>
                  <.stripe_form
                    :if={@client_secret}
                    id={"#{@id}-form-4"}
                    phx-submit={lock_while_paying() |> JS.push("pay")}
                    client_secret={@client_secret}
                    customer_session_client_secret={@customer_session_client_secret}
                    return_url={url(~p"/checkout/complete/#{@order.id}")}
                    billing_name={@order.customer_name}
                    billing_email={@order.customer_email}
                    billing_phone={buyer_phone_number(@order)}
                    on_loading={lock_while_paying()}
                    on_ready={unlock_after_paying(%JS{})}
                    busy_label={~t"Tying the ribbon…"}
                  >
                    <:before_button>
                      <.recurring_charge order={@order} fee={delivery_fee(@order, @delivery_quote)} />
                    </:before_button>
                    {~t"Pay"} {Edenflowers.Format.currency(@order.grand_total, @order.locale)}
                  </.stripe_form>

                  <p :if={!@client_secret} class="text-error" data-testid="stripe-unavailable">
                    {~t"Payment is temporarily unavailable. Please try again in a moment."}
                  </p>
                </.checkout_step>
              </.steps>
            </div>

            <div class="md:w-[20rem] md:sticky md:top-8 md:h-fit lg:w-[22rem]">
              <section class="flex flex-col gap-6 pt-8 md:pt-10" data-testid="cart-section" data-locked-while-paying>
                <p class="eyebrow text-base-content/70" data-testid="cart-heading">
                  {~t"Cart"} ({@order.total_items_in_cart})
                </p>

                <.live_component id="checkout-line-items" module={EdenflowersWeb.Cart.LineItems} order={@order} />

                <div class="border-base-content/12 border-t"></div>

                <.live_component
                  id="checkout-promo"
                  module={EdenflowersWeb.Cart.PromoCode}
                  order={@order}
                  current_user={@current_user}
                  show_applied={false}
                />

                <div class="flex flex-col gap-2 text-base">
                  <.delivery_cost
                    fee={delivery_fee(@order, @delivery_quote)}
                    distance={delivery_distance(@order, @delivery_quote)}
                    locale={@order.locale}
                  />

                  <div
                    :if={@order.promotion_applied?}
                    class="flex items-baseline justify-between"
                    data-testid="discount-section"
                  >
                    <span class="flex items-baseline gap-2">
                      {~t"Discount"}
                      <EdenflowersWeb.Cart.PromoCode.badge code={@order.promotion_code} target="#checkout-promo" />
                    </span>
                    <span class="text-success tabular-nums" data-testid="discount-amount">
                      - {Edenflowers.Format.currency(@order.discount, @order.locale)}
                    </span>
                  </div>

                  <p
                    :if={@order.promotion_applied? and @order.subscription?}
                    class="text-base-content/70 text-sm"
                    data-testid="first-delivery-discount"
                  >
                    {~t"The discount applies to your first delivery."}
                  </p>

                  <div
                    class="flex items-baseline justify-between font-semibold"
                    data-testid="order-total"
                  >
                    <span>{~t"Total"}</span>
                    <span class="tabular-nums" data-testid="total-amount">
                      {Edenflowers.Format.currency(total(@order, @delivery_quote), @order.locale)}
                    </span>
                  </div>

                  <div
                    :if={Decimal.gt?(vat(@order, @delivery_quote), 0)}
                    class="text-base-content/70 flex items-baseline justify-between"
                    data-testid="vat-line"
                  >
                    <span>{~t"Includes VAT"}</span>
                    <span class="tabular-nums">
                      {Edenflowers.Format.currency(vat(@order, @delivery_quote), @order.locale)}
                    </span>
                  </div>
                </div>
              </section>
            </div>
          </div>
        </div>
      </.container>

      <.card_drawer
        variants={@card_variants}
        locale={@order.locale}
        selected_variant_id={Enum.find_value(@order.line_items, &(&1.is_card && &1.product_variant_id))}
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate_form", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("format_phone_number", %{"value" => typed}, socket) do
    case PhoneNumber.format(typed) do
      {:ok, formatted} ->
        params = Map.put(socket.assigns.form.params, "recipient_phone_number", formatted)
        {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}

      :error ->
        {:noreply, socket}
    end
  end

  # AddressInput keeps its own state, so the parent only learns the typed
  # address on submit.
  def handle_event("save_form", %{"form" => params} = all_params, %{assigns: %{order: %{state: :delivery}}} = socket) do
    params =
      case all_params do
        %{"delivery_address" => address} -> Map.put(params, "delivery_address", address)
        _ -> params
      end

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, order} ->
        next_section_id = next_section_id(socket.assigns.id, order.state)

        {:noreply,
         socket
         |> reload_order()
         |> push_patch(to: step_path(order.state))
         |> push_event("focus-element", %{id: next_section_id})}

      {:error, form} ->
        forward_delivery_address_error(form)
        focus_first_error()
        # A rejected date may have just been closed, so refresh the calendar.
        {:noreply, socket |> reload_order() |> assign(form: form)}
    end
  end

  def handle_event("save_form", %{"form" => params}, socket) do
    submit_form(socket, params)
  end

  # Mount and the cart-change broadcast already send these carts away; this
  # catches a click that lands before the broadcast does.
  def handle_event("pay", _, %{assigns: %{order: %{add_ons_only?: true}}} = socket) do
    {:noreply, back_to_store(socket)}
  end

  def handle_event("pay", _, %{assigns: %{client_secret: nil}} = socket) do
    {:noreply, put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please try again in a moment.")}
  end

  # Others may have bought the last of a size since it went in the cart.
  def handle_event("pay", _, socket) do
    order = Ash.load!(socket.assigns.order, [line_items: [:over_stock?, :product_variant]], actor: actor(socket))

    case Enum.filter(order.line_items, & &1.over_stock?) do
      [] ->
        pay(socket)

      lines ->
        {:noreply,
         socket
         |> put_flash(:error, over_stock_message(lines))
         |> push_event("stripe:ready", %{})}
    end
  end

  def handle_event("edit_step", %{"state" => state}, socket) do
    {:noreply, push_patch(socket, to: ~p"/checkout?step=#{state}")}
  end

  # A day that isn't open is still clickable, only marked aria-disabled.
  def handle_event("select-date", %{"date" => date}, socket) do
    with {:ok, date} <- Date.from_iso8601(date),
         :open <- Availability.customer_cell_state(socket.assigns.shop_calendar, date) do
      form = AshPhoenix.Form.update_params(socket.assigns.form, &Map.put(&1, "fulfillment_date", Date.to_iso8601(date)))
      {:noreply, assign(socket, form: form)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("update_fulfillment_option", %{"form" => %{"fulfillment_option_id" => id}}, socket) do
    previous_method = socket.assigns.order.fulfillment_method
    Orders.update_fulfillment_option!(socket.assigns.order, id, actor: actor(socket))
    socket = reload_order(socket)

    # Switching to pickup unmounts the address field. It remounts with
    # whatever address the order holds, which may be prefilled.
    case socket.assigns.order.fulfillment_method do
      :pickup ->
        {:noreply, assign(socket, delivery_quote: nil)}

      :delivery when previous_method == :pickup ->
        {:noreply, assign(socket, delivery_quote: quote_from_order(socket.assigns.order))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_gift", %{"form" => %{"gift" => gift}}, socket) do
    Orders.set_gift!(socket.assigns.order, gift, actor: actor(socket))
    {:noreply, reload_order(socket)}
  end

  def handle_event("select_card", %{"variant-id" => variant_id}, socket) do
    variant = Enum.find(socket.assigns.card_variants, &(&1.id == variant_id))
    Orders.add_card!(socket.assigns.order, variant.id, actor: actor(socket))
    {:noreply, reload_order(socket)}
  end

  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error("Stripe client error for order #{socket.assigns.order.id}: #{message}: #{inspect(details)}")

    {:noreply,
     put_flash(
       socket,
       :error,
       ~t"Payment is temporarily unavailable. Please refresh the page and try again."
     )}
  end

  # The `pay` handler syncs the PaymentIntent amount, so only a switch between
  # one-off and subscription, which changes card saving, replaces it here.
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> _}, socket) do
    order = Orders.get_order_for_checkout!(socket.assigns.order.id, actor: actor(socket))

    if order.add_ons_only?, do: {:noreply, back_to_store(socket)}, else: apply_cart_change(socket, order)
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:checkout_restarted:" <> _}, socket) do
    {:noreply, push_navigate(socket, to: ~q"/#{language}")}
  end

  def handle_info(:focus_first_error, socket) do
    {:noreply, push_event(socket, "focus-first-error", %{})}
  end

  def handle_info({:delivery_quoted, quote}, socket) do
    {:noreply, assign(socket, delivery_quote: quote)}
  end

  defp apply_cart_change(socket, order) do
    payment_mode_changed? = socket.assigns.order.subscription? != order.subscription?

    # A card removed from the cart takes its message with it; drop the typed
    # value too, or it would reappear if a card is picked again.
    socket =
      if has_card?(socket.assigns.order) and not has_card?(order) do
        assign_forms(socket, order, drop: ["card_message"])
      else
        assign(socket, order: order)
      end

    socket = if payment_mode_changed?, do: maybe_setup_payment(socket, order, actor(socket)), else: socket

    {:noreply, socket}
  end

  defp back_to_store(socket) do
    socket
    |> put_flash(:info, ~t"Add-ons are sold with flowers. Add a bouquet to check out.")
    |> push_navigate(to: ~q"/#{language}/store")
  end

  defp submit_action_for(:contact_details), do: :submit_contact_details
  defp submit_action_for(:gift_options), do: :submit_gift_options
  defp submit_action_for(:delivery), do: :submit_delivery
  defp submit_action_for(:payment), do: nil

  attr :order, :map, required: true
  attr :id, :string, required: true
  attr :state, :atom, required: true
  attr :testid, :string, default: nil
  slot :inner_block, required: true

  defp checkout_step(assigns) do
    ~H"""
    <section
      :if={@order.state == @state}
      id={section_id(@id, @state)}
      class="scroll-anchor-below-header mb-12 flex flex-col gap-8"
      data-testid={@testid}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp field_errors(assigns) do
    ~H"""
    <.error :for={msg <- field_error_messages(@field)}>{msg}</.error>
    """
  end

  defp field_error_messages(field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &translate_error/1),
      else: []
  end

  attr :order, :map, required: true
  attr :form, :map, required: true
  attr :id, :string, required: true
  attr :card_variants, :list, required: true

  defp gift_card_slot(assigns) do
    card_line_item = Enum.find(assigns.order.line_items, & &1.is_card)

    assigns =
      assigns
      |> assign(:card_line_item, card_line_item)
      |> assign(:recipient_first_name, recipient_first_name(assigns.form[:recipient_name].value))
      |> assign(
        :card_message_max,
        card_line_item && ProductVariantSize.max_message_length(card_line_item.variant_size)
      )
      |> assign(:card_from_price, card_from_price(assigns.card_variants, assigns.order.locale))

    ~H"""
    <div :if={@order.gift} class="flex flex-col gap-4" data-testid="card-selection">
      <div :if={@card_line_item} data-testid="card-preview">
        <fieldset
          id={"#{@id}-field-card-message"}
          phx-hook="CharacterCount"
          data-testid="card-message-field"
          class="flex flex-col"
        >
          <label for={"#{@id}-card-message"} class="mb-1">{gettext("Card message")}</label>
          <%!-- The input is styled as the card itself, matching the thank-you page's card,
               so the customer sees their words as the recipient will. --%>
          <div class="bg-cream text-cream-content relative px-7 py-6 has-[textarea:focus-visible]:outline-primary has-[textarea:focus-visible]:outline-2 has-[textarea:focus-visible]:outline-offset-2">
            <%!-- Hidden rather than removed: adding or removing it makes LiveView move the
                 card image below, which replays its tuck-in animation. --%>
            <p
              hidden={is_nil(@recipient_first_name)}
              class="mb-3 pr-24 text-sm"
              aria-hidden="true"
              data-testid="card-message-recipient"
            >
              {@recipient_first_name && ~t"For #{@recipient_first_name}"}
            </p>
            <textarea
              id={"#{@id}-card-message"}
              name={@form[:card_message].name}
              class="font-serif w-full resize-none bg-transparent pr-24 text-xl italic leading-snug placeholder:text-cream-content/50 focus:outline-none"
              maxlength={@card_message_max}
              aria-describedby={"#{@id}-card-message-count"}
              placeholder={~t"Write your message…"}
              rows={5}
              data-testid="card-message-textarea"
            >{Phoenix.HTML.Form.normalize_value("textarea", @form[:card_message].value)}</textarea>
            <%!-- Keyed on the chosen card so a new pick replaces the element and replays the tuck-in. --%>
            <button
              id={"card-image-#{@card_line_item.product_variant_id}"}
              type="button"
              phx-click={JS.exec("phx-show", to: "#card-drawer")}
              aria-haspopup="dialog"
              class="card-tuck absolute top-4 right-4"
              data-testid="card-image-button"
              title={gettext("Change card")}
            >
              <.image
                src={@card_line_item.product_image_slug}
                alt=""
                width={80}
                height={80}
                sizes="80px"
                class="h-20 w-20 object-cover"
              />
              <span class="sr-only">{gettext("Change card")}</span>
            </button>
            <div id={"#{@id}-card-message-count"} class="text-cream-content/60 flex justify-end text-xs">
              <span id="char-count" phx-update="ignore">0</span>/{@card_message_max}
            </div>
          </div>
          <.field_errors field={@form[:card_message]} />
        </fieldset>
      </div>

      <button
        :if={is_nil(@card_line_item)}
        type="button"
        phx-click={JS.exec("phx-show", to: "#card-drawer")}
        aria-haspopup="dialog"
        class="press border-base-300 flex w-full items-center gap-4 border px-4 py-3 text-left hover:border-primary"
        data-testid="select-card-button"
      >
        <.icon name="hero-gift" class="h-6 w-6 shrink-0" />
        <span class="flex flex-col">
          <span>{~t"Add a card"}</span>
          <span :if={@card_from_price} class="text-base-content/70 text-sm">
            {~t"From #{@card_from_price}, with your personal message"}
          </span>
        </span>
        <.icon name="hero-chevron-right" class="ml-auto h-5 w-5 shrink-0" />
      </button>

      <p :if={@order.subscription?} class="text-base-content/70 text-sm" data-testid="first-delivery-card">
        {~t"The card comes with your first delivery."}
      </p>
    </div>
    """
  end

  attr :order, :map, required: true
  attr :fee, :any, required: true

  # Saying what the saved card will be charged, and how often, is the consent
  # for every later charge, so it sits right above the button that gives it.
  defp recurring_charge(assigns) do
    %{order: order, fee: fee} = assigns

    case Enum.find(order.line_items, & &1.interval_weeks) do
      %{} = line when not is_nil(order.fulfillment_date) ->
        assigns =
          assign(assigns,
            amount: Edenflowers.Format.currency(Decimal.add(line.subtotal, fee || 0), order.locale),
            interval: String.downcase(EdenflowersWeb.Checkout.Fields.interval_label(line.interval_weeks)),
            from:
              Edenflowers.Format.weekday_date(Date.add(order.fulfillment_date, line.interval_weeks * 7), order.locale)
          )

        ~H"""
        <p class="text-base-content/80 text-sm leading-relaxed" data-testid="recurring-charge">
          {~t"Then #{amount = @amount} #{interval = @interval} from #{date = @from}, charged #{days = Edenflowers.Orders.Subscription.lead_days()} days before each delivery. Pause or cancel anytime."}
        </p>
        """

      _not_a_subscription ->
        ~H""
    end
  end

  defp card_from_price([], _locale), do: nil

  defp card_from_price(card_variants, locale) do
    card_variants
    |> Enum.min_by(& &1.price, Decimal)
    |> Map.fetch!(:price)
    |> Edenflowers.Format.currency(locale)
  end

  defp pay(socket) do
    case Payments.update_amount(socket.assigns.order) do
      {:ok, _payment_intent} ->
        {:noreply, push_event(socket, "stripe:process_payment", %{})}

      {:error, error} ->
        Logger.error("Failed to update PaymentIntent for order #{socket.assigns.order.id}: #{inspect(error)}")

        {:noreply,
         socket
         |> put_flash(:error, ~t"Payment processing error. Please try again.")
         |> push_event("stripe:ready", %{})}
    end
  end

  defp over_stock_message(lines) do
    shortages =
      Enum.map_join(lines, " ", fn line_item ->
        product = line_item.product_name
        stock = WithinStock.message(line_item.product_variant.stock_quantity)
        ~t"#{product}: #{stock}."
      end)

    shortages <> " " <> ~t"Change your cart to continue."
  end

  defp has_card?(order), do: Enum.any?(order.line_items, & &1.is_card)

  attr :fee, :any, required: true
  attr :distance, :integer, default: nil
  attr :locale, :string, required: true

  defp delivery_cost(assigns) do
    ~H"""
    <div class="flex items-baseline justify-between" data-testid="delivery-cost">
      <span>
        {~t"Delivery"}
        <span :if={@distance} class="text-base-content/65 ml-1 text-sm tabular-nums">
          {Edenflowers.Format.distance(@distance, @locale)}
        </span>
      </span>
      <%= cond do %>
        <% is_nil(@fee) -> %>
          <span class="text-base-content/70">—</span>
        <% Decimal.eq?(@fee, 0) -> %>
          <span>{~t"Free"}</span>
        <% true -> %>
          <span class="tabular-nums">{Edenflowers.Format.currency(@fee, @locale)}</span>
      <% end %>
    </div>
    """
  end

  # A geocode saved by an earlier submit stands as the quote when the
  # customer comes back to the delivery step.
  defp quote_from_order(%{delivery_address: address, geocoded_address: geocoded_address, distance: distance})
       when is_integer(distance),
       do: %{address: address, geocoded_address: geocoded_address, distance: distance}

  defp quote_from_order(_order), do: nil

  defp delivery_distance(%{fulfillment_method: :delivery}, %{distance: distance}), do: distance
  defp delivery_distance(_order, _quote), do: nil

  # Until the delivery step is submitted the order has no fee, so the summary
  # prices the quote, against the cart as it is now. After that the order's
  # own fee is what Stripe charges.
  defp delivery_fee(%{state: :delivery, fulfillment_method: :pickup, fulfillment_option: %{} = option}, _quote),
    do: Fee.calculate(option, 0).fulfillment_fee

  defp delivery_fee(%{state: :delivery, fulfillment_option: %{} = option} = order, %{distance: distance}) do
    quoted = Fee.calculate(option, distance)
    Orders.charged_fulfillment_fee!(quoted.fulfillment_fee, quoted.in_free_delivery_zone, order.free_delivery?)
  end

  defp delivery_fee(%{state: :delivery}, _quote), do: nil
  defp delivery_fee(order, _quote), do: order.fulfillment_fee

  defp total(order, quote), do: Decimal.add(order.items_total, delivery_fee(order, quote) || 0)

  defp vat(order, quote), do: Vat.total(%{order | fulfillment_fee: delivery_fee(order, quote)})

  defp handle_mount_error(socket, log_message, flash_message) do
    Logger.error(log_message)

    {:ok,
     socket
     |> put_flash(:error, flash_message)
     |> push_navigate(to: ~q"/#{language}")}
  end

  defp recipient_first_name(recipient_name) do
    {:ok, first_name} =
      Ash.calculate(Order, :recipient_first_name, refs: %{recipient_name: recipient_name}, authorize?: false)

    first_name
  end

  # Only a gift delivery asks for the recipient's details; otherwise the number is the buyer's.
  defp recipient_label(%{gift: true, fulfillment_method: :delivery, recipient_first_name: first_name}, field)
       when is_binary(first_name) do
    case field do
      :address -> gettext("%{name}'s address *", name: first_name)
      :phone -> gettext("%{name}'s phone number *", name: first_name)
    end
  end

  defp recipient_label(order, field) do
    case {field, order.fulfillment_method} do
      {:address, _} -> gettext("Address *")
      {:phone, _} -> gettext("Phone number *")
    end
  end

  defp phone_help(%{fulfillment_method: :pickup}),
    do: gettext("I'll send a message when your order is ready for pick up.")

  defp phone_help(%{gift: true, fulfillment_method: :delivery, recipient_first_name: first_name})
       when is_binary(first_name),
       do: gettext("I'll only call if I need to reach %{name} about the delivery.", name: first_name)

  defp phone_help(_order), do: gettext("I'll only call if I need to reach you about the delivery.")

  # The form's own value is the changeset's already-formatted number. Rendering
  # that while typing leaves the value attribute unchanged when the blur handler
  # formats it, so LiveView never repaints the box. Show what was typed until blur.
  defp typed_phone_number(form) do
    Map.get(form.params, "recipient_phone_number", form[:recipient_phone_number].value)
  end

  # Stripe needs the country code to hand the number to Link.
  defp buyer_phone_number(%{gift: true, fulfillment_method: :delivery}), do: nil

  defp buyer_phone_number(order) do
    case Edenflowers.PhoneNumber.format(order.recipient_phone_number, :e164) do
      {:ok, e164} -> e164
      :error -> nil
    end
  end

  # Autofill offers the buyer's own saved details, which are wrong for a gift's recipient.
  defp own_details_autocomplete(%{gift: true, fulfillment_method: :delivery}, _token), do: "off"
  defp own_details_autocomplete(_order, token), do: token

  # The order only knows its customer once step 1 is submitted, so signed-in
  # customers need the same check up front or the offer flashes then vanishes.
  defp hide_newsletter_offer?(order, current_user) do
    order.newsletter_offer_hidden? or (current_user != nil and current_user.newsletter_offer_hidden?)
  end

  defp load_newsletter_offer_hidden(nil), do: nil
  defp load_newsletter_offer_hidden(user), do: Ash.load!(user, :newsletter_offer_hidden?, actor: user)

  defp actor(socket), do: socket.assigns[:current_user]

  defp make_form(order, action, params) do
    order
    |> AshPhoenix.Form.for_update(action, params: params)
    |> to_form()
  end

  # Signed-in customers shouldn't retype details we already hold. Anything
  # already saved on the order wins, so returning to step 1 after an edit keeps
  # what was typed there.
  defp prefill_contact_details(%{state: :contact_details} = order, %{} = user) do
    %{
      "customer_name" => order.customer_name || user.name,
      "customer_email" => order.customer_email || to_string(user.email)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp prefill_contact_details(_order, _user), do: %{}

  # Nil on the payment step, which Stripe Elements drives.
  defp build_submit_form(order, params) do
    case submit_action_for(order.state) do
      nil -> nil
      action -> make_form(order, action, params)
    end
  end

  # Keeps unsaved input across a reload. `drop` discards params the action just
  # cleared, which would otherwise shadow the cleared attribute.
  defp assign_forms(socket, order, opts) do
    drop = Keyword.get(opts, :drop, [])

    form_params =
      case socket.assigns[:form] do
        nil -> %{}
        form -> Map.drop(form.params, drop)
      end

    socket
    |> assign(order: order)
    |> assign(form: build_submit_form(order, form_params))
  end

  defp submit_form(socket, params) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, order} ->
        next_section_id = next_section_id(socket.assigns.id, order.state)

        {:noreply,
         socket
         |> reload_order()
         |> push_patch(to: step_path(order.state))
         |> push_event("focus-element", %{id: next_section_id})}

      {:error, form} ->
        focus_first_error()
        {:noreply, assign(socket, form: form)}
    end
  end

  # Sent as a message rather than pushed directly so it lands after any
  # send_update from forward_delivery_address_error, whose errors render in a
  # later diff.
  defp focus_first_error, do: send(self(), :focus_first_error)

  defp forward_delivery_address_error(form) do
    case form[:delivery_address].errors do
      [error | _] ->
        send_update(EdenflowersWeb.Checkout.AddressInput,
          id: "address-input",
          error_message: translate_error(error)
        )

      _ ->
        :ok
    end
  end

  defp reload_order(socket, opts \\ []) do
    order = Orders.get_order_for_checkout!(socket.assigns.order.id, actor: actor(socket))
    order = ensure_fulfillment_default(order, socket.assigns.fulfillment_options, actor(socket))

    socket
    |> maybe_quote_on_entering_delivery(order)
    |> assign_forms(order, opts)
    |> ensure_payment_for_state(order, actor(socket))
  end

  # The address field mounts fresh on the delivery step with the order's
  # address, which may be prefilled, so the quote has to match it.
  defp maybe_quote_on_entering_delivery(%{assigns: %{order: %{state: :delivery}}} = socket, _order), do: socket

  defp maybe_quote_on_entering_delivery(socket, %{state: :delivery} = order),
    do: assign(socket, delivery_quote: quote_from_order(order))

  defp maybe_quote_on_entering_delivery(socket, _order), do: socket

  # Persisted (not just visual) so the dependent form-3b renders and the
  # value flows through on submit. Re-read afterwards: the update's result
  # still holds the unset fulfillment_option and totals from before it.
  defp ensure_fulfillment_default(%{state: :delivery, fulfillment_option_id: nil} = order, options, actor) do
    case List.first(options) do
      nil ->
        order

      %{id: id} ->
        Orders.update_fulfillment_option!(order, id, actor: actor)
        Orders.get_order_for_checkout!(order.id, actor: actor)
    end
  end

  defp ensure_fulfillment_default(order, _options, _actor), do: order

  defp validate_cart_not_empty(%{cart_effectively_empty?: true}), do: {:error, :empty_cart}
  defp validate_cart_not_empty(_order), do: :ok

  defp validate_not_add_ons_only(%{add_ons_only?: true}), do: {:error, :add_ons_only}
  defp validate_not_add_ons_only(_order), do: :ok

  defp lock_while_paying(js \\ %JS{}), do: JS.set_attribute(js, {"inert", ""}, to: @locked_while_paying)

  defp unlock_after_paying(js), do: JS.remove_attribute(js, "inert", to: @locked_while_paying)

  defp section_id(id, state) when state in @checkout_states do
    "#{id}-section-#{state}"
  end

  defp next_section_id(id, state) when state in @checkout_states, do: section_id(id, state)
  defp next_section_id(_, _), do: nil

  defp step_index(state), do: Enum.find_index(@checkout_states, &(&1 == state))

  defp step_path(state), do: ~p"/checkout?step=#{state}"

  # Replaced rather than pushed, so a correction adds no history entry for back to return to.
  defp correct_step_url(socket) do
    if connected?(socket) do
      push_patch(socket, to: step_path(socket.assigns.order.state), replace: true)
    else
      socket
    end
  end

  # Returning to checkout mid-way lands the customer on the step they left.
  # No focus: on a phone it would open the keyboard before they see the page.
  defp maybe_scroll_to_current_step(%{assigns: %{order: %{state: :contact_details}}} = socket), do: socket

  defp maybe_scroll_to_current_step(socket) do
    if connected?(socket) do
      push_event(socket, "focus-element", %{id: section_id(socket.assigns.id, socket.assigns.order.state), focus: false})
    else
      socket
    end
  end

  defp maybe_setup_payment(socket, %{state: :payment} = order, actor) do
    case Payments.setup(order, actor) do
      {:ok, order, client_secret} ->
        socket
        |> assign(order: order)
        |> assign(client_secret: client_secret)
        |> assign(customer_session_client_secret: customer_session(socket, order, actor))

      {:error, _reason} ->
        payment_unavailable(socket)
    end
  end

  defp maybe_setup_payment(socket, _order, _actor), do: socket

  # The Payment Element only starts once connected, so a CustomerSession made
  # for the static render would go unused.
  defp customer_session(socket, order, actor) do
    if connected?(socket), do: Payments.customer_session(order, actor)
  end

  defp ensure_payment_for_state(socket, %{state: :payment} = order, actor) do
    if socket.assigns[:client_secret] do
      socket
    else
      maybe_setup_payment(socket, order, actor)
    end
  end

  defp ensure_payment_for_state(socket, _order, _actor), do: socket

  defp payment_unavailable(socket) do
    socket
    |> assign(client_secret: nil, customer_session_client_secret: nil)
    |> put_flash(:error, ~t"Payment is temporarily unavailable. Please try again in a moment.")
  end
end
