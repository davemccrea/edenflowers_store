defmodule EdenflowersWeb.CheckoutLive do
  use EdenflowersWeb, :live_view

  require Logger

  alias Edenflowers.Store.{Order, FulfillmentOption, ProductVariant, ProductVariantSize}
  alias Edenflowers.Fulfillments

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.StripeAPI)
  defp stripe_publishable_key, do: Application.get_env(:edenflowers, :stripe_publishable_key)

  defp submit_action_for(:contact_details), do: :submit_contact_details
  defp submit_action_for(:gift_options), do: :submit_gift_options
  defp submit_action_for(:delivery), do: :submit_delivery
  defp submit_action_for(:payment), do: nil

  defp state_index(state), do: Enum.find_index(@checkout_states, &(&1 == state))

  def mount(_params, _session, %{assigns: %{order: order}} = socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "line_item:changed:#{order.id}")
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:checkout_restarted:#{order.id}")
    end

    with :ok <- cart_has_items?(order),
         {:ok, fulfillment_options} <- FulfillmentOption.list_for_checkout() do
      order = ensure_fulfillment_default(order, fulfillment_options, socket.assigns[:current_user])
      card_variants = ProductVariant.for_card_drawer!()

      {:ok,
       socket
       |> assign(:id, "checkout")
       |> assign(:page_title, ~t"Checkout")
       |> assign(:fulfillment_options, fulfillment_options)
       |> assign(:card_variants, card_variants)
       |> assign(:order, order)
       |> assign(:form, build_submit_form(order))
       |> assign(:client_secret, nil)
       |> maybe_setup_stripe(order)}
    else
      {:error, :empty_cart} ->
        # Mounting with an effectively-empty cart means the customer either
        # navigated here directly or returned after another tab emptied the
        # cart. Reset before bouncing so a stale step/card/contact details
        # don't survive into the next checkout.
        Order.restart_checkout!(order, actor: socket.assigns[:current_user])
        handle_mount_error(socket, "Cart is empty", ~t"Cart is empty")

      error ->
        Logger.error("Error loading checkout: #{inspect(error)}")
        handle_mount_error(socket, "Error loading checkout", ~t"Error loading checkout")
    end
  end

  # ======
  # Markup
  # ======

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
              <.steps state={@order.state} order={@order}>
                <section
                  :if={@order.state == :contact_details}
                  id={"#{@id}-section-1"}
                  class="scroll-anchor-below-header mb-12 flex flex-col gap-8"
                  data-testid="checkout-step-1"
                >
                  <.form
                    id={"#{@id}-form-1"}
                    for={@form}
                    phx-change="validate_form"
                    phx-submit="save_form"
                    class="flex flex-col space-y-6"
                    data-testid="checkout-form-1"
                  >
                    <.input
                      label={~t"Your Name *"}
                      field={@form[:customer_name]}
                      type="text"
                      data-testid="customer-name-input"
                    />
                    <.input
                      label={~t"Email *"}
                      field={@form[:customer_email]}
                      type="email"
                      data-testid="customer-email-input"
                    />

                    <.form_button data-testid="step-1-next-button">{~t"Next"}</.form_button>
                  </.form>
                </section>

                <section
                  :if={@order.state == :gift_options}
                  id={"#{@id}-section-2"}
                  class="scroll-anchor-below-header mb-12 flex flex-col gap-8"
                  data-testid="checkout-step-2"
                >
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
                      label={~t"Recipient Name *"}
                      field={@form[:recipient_name]}
                      type="text"
                      data-testid="recipient-name-input"
                    />

                    <.gift_card_slot order={@order} form={@form} id={@id} />

                    <.form_button>{gettext("Next")}</.form_button>
                  </.form>
                </section>

                <section
                  :if={@order.state == :delivery}
                  id={"#{@id}-section-3"}
                  class="scroll-anchor-below-header mb-12 flex flex-col gap-8"
                >
                  <.form id={"#{@id}-form-3a"} for={%{}} phx-change="update_fulfillment_option">
                    <.input
                      :let={option}
                      type="radio-card"
                      field={@form[:fulfillment_option_id]}
                      options={Enum.map(@fulfillment_options, fn %{id: id, name: name} -> %{name: name, value: id} end)}
                      label={~t"Delivery Method *"}
                    >
                      {option.name}
                    </.input>
                  </.form>

                  <%= if not is_nil(@order.fulfillment_option) do %>
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
                        module={EdenflowersWeb.AddressInputComponent}
                        order={@order}
                        label={recipient_label(@order, "address")}
                      />

                      <.input
                        :if={@order.fulfillment_method == :delivery}
                        label={~t"Delivery Instructions"}
                        field={@form[:delivery_instructions]}
                        type="text"
                        placeholder={~t"e.g. Door code 1234, leave at the front door"}
                      />

                      <.input
                        label={recipient_label(@order, "phone")}
                        placeholder={~t"045 1505141"}
                        field={@form[:recipient_phone_number]}
                        type="tel"
                      />

                      <fieldset class="flex flex-col">
                        <label class="mb-1">
                          <%= if @order.fulfillment_method == :delivery do %>
                            {~t"Delivery Date *"}
                          <% else %>
                            {~t"Pickup Date *"}
                          <% end %>
                        </label>
                        <.live_component
                          id="calendar"
                          error={
                            Phoenix.Component.used_input?(@form[:fulfillment_date]) and
                              Enum.any?(@form[:fulfillment_date].errors)
                          }
                          selected_date={@form[:fulfillment_date].value}
                          module={EdenflowersWeb.CalendarComponent}
                          selectable?={
                            fn date ->
                              {fulfillable?, _reason} =
                                Fulfillments.fulfill_on_date(@order.fulfillment_option, date)

                              fulfillable?
                            end
                          }
                        >
                          <:day_decoration :let={day}>
                            <.icon
                              :if={day == ~D[2025-05-07]}
                              name="hero-heart-solid"
                              class="text-error absolute top-0 right-0 left-0 m-auto h-3 w-3 translate-y-0.5"
                            />
                          </:day_decoration>
                        </.live_component>
                        <.field_errors field={@form[:fulfillment_date]} />
                        <.input field={@form[:fulfillment_date]} hidden />
                      </fieldset>

                      <.form_button>{~t"Next"}</.form_button>
                    </.form>
                  <% end %>
                </section>

                <section
                  :if={@order.state == :payment}
                  id={"#{@id}-section-4"}
                  class="scroll-anchor-below-header mb-12 flex flex-col gap-8"
                >
                  <form
                    :if={@client_secret}
                    id={"#{@id}-form-4"}
                    phx-hook="Stripe"
                    phx-submit="save_form_4"
                    data-client-secret={@client_secret}
                    data-publishable-key={stripe_publishable_key()}
                    data-return-url={url(~p"/checkout/complete/#{@order.id}")}
                    data-stripe-loading={JS.set_attribute({"disabled", "true"}, to: "#payment-button")}
                    data-stripe-ready={JS.remove_attribute("disabled", to: "#payment-button")}
                    class="flex flex-col gap-4"
                  >
                    <div phx-update="ignore" id="payment-element"></div>
                    <div phx-update="ignore" id="stripe-error-message" class="text-error"></div>

                    <.form_button disabled={true} id="payment-button">
                      {~t"Pay"} {Edenflowers.Utils.format_money(@order.grand_total)}
                    </.form_button>
                  </form>

                  <p :if={!@client_secret} class="text-error" data-testid="stripe-unavailable">
                    {~t"Payment is temporarily unavailable. Please try again in a moment."}
                  </p>
                </section>
              </.steps>
            </div>

            <div class="md:w-[20rem] md:sticky md:top-8 md:h-fit lg:w-[22rem]">
              <section class="flex flex-col gap-6 pt-8 md:pt-10" data-testid="cart-section">
                <p class="eyebrow text-base-content/60" data-testid="cart-heading">
                  {~t"Cart"} ({@order.total_items_in_cart || 0})
                </p>

                <.live_component id="checkout-line-items" module={EdenflowersWeb.LineItemsComponent} order={@order} />

                <.live_component
                  id="checkout-promo"
                  module={EdenflowersWeb.PromoCodeComponent}
                  order={@order}
                  current_user={@current_user}
                />

                <div class="border-base-content/12 border-t"></div>

                <div class="flex flex-col gap-2 text-base">
                  <div class="flex items-baseline justify-between" data-testid="delivery-cost">
                    <span>{~t"Delivery"}</span>
                    <%= cond do %>
                      <% is_nil(@order.fulfillment_fee) -> %>
                        <span class="text-base-content/60">—</span>
                      <% Decimal.eq?(@order.fulfillment_fee, 0) -> %>
                        <span>{~t"Free"}</span>
                      <% true -> %>
                        <span class="tabular-nums">{Edenflowers.Utils.format_money(@order.fulfillment_fee)}</span>
                    <% end %>
                  </div>

                  <div
                    :if={@order.promotion_applied?}
                    class="flex items-baseline justify-between"
                    data-testid="discount-section"
                  >
                    <span>{~t"Discount"}</span>
                    <span class="text-success tabular-nums" data-testid="discount-amount">
                      - {Edenflowers.Utils.format_money(@order.discount)}
                    </span>
                  </div>

                  <div
                    :if={@order.tax && Decimal.gt?(@order.tax, 0)}
                    class="flex items-baseline justify-between"
                    data-testid="vat-line"
                  >
                    <span>{~t"Incl. VAT"}</span>
                    <span class="tabular-nums">{Edenflowers.Utils.format_money(@order.tax)}</span>
                  </div>

                  <div class="mt-3 flex items-baseline justify-between font-semibold" data-testid="order-total">
                    <span>{~t"Total"}</span>
                    <span class="tabular-nums" data-testid="total-amount">
                      {Edenflowers.Utils.format_money(@order.grand_total)}
                    </span>
                  </div>
                </div>
              </section>
            </div>
          </div>
        </div>
      </.container>

      <.card_drawer variants={@card_variants} />
    </Layouts.app>
    """
  end

  attr :order, :map, required: true
  attr :form, :map, required: true
  attr :id, :string, required: true

  defp gift_card_slot(assigns) do
    card_line_item = Enum.find(assigns.order.line_items, & &1.is_card)

    assigns =
      assigns
      |> assign(:card_line_item, card_line_item)
      |> assign(
        :card_message_max,
        card_line_item && ProductVariantSize.max_message_length(card_line_item.variant_size)
      )

    ~H"""
    <div :if={@order.gift} class="flex flex-col gap-4" data-testid="card-selection">
      <div :if={@card_line_item} data-testid="card-preview">
        <fieldset
          id={"#{@id}-field-card-message"}
          phx-hook="CharacterCount"
          data-testid="card-message-field"
          class="flex flex-col"
        >
          <label for={"#{@id}-card-message"} class="mb-1">{gettext("Card Message")}</label>
          <div class="textarea textarea-lg relative w-full">
            <div class="relative w-full">
              <textarea
                id={"#{@id}-card-message"}
                name={@form[:card_message].name}
                class="h-full w-full resize-none bg-transparent pr-20 focus:outline-none"
                maxlength={@card_message_max}
                rows={5}
                data-testid="card-message-textarea"
              >{Phoenix.HTML.Form.normalize_value("textarea", @form[:card_message].value)}</textarea>
              <div class="absolute top-2 right-2">
                <div class="relative">
                  <button
                    type="button"
                    phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#card-drawer")}
                    class="block shrink-0 cursor-pointer"
                    data-testid="card-image-button"
                    title={gettext("Change card")}
                  >
                    <.image
                      src={@card_line_item.product_image_slug}
                      alt={@card_line_item.product_name}
                      width={80}
                      height={80}
                      sizes="80px"
                      class="h-20 w-20 object-cover transition-opacity hover:opacity-70"
                    />
                  </button>
                  <button
                    type="button"
                    phx-click="remove_card"
                    class="text-base-content/70 bg-base-100 absolute -top-2 -right-2 flex h-7 w-7 cursor-pointer items-center justify-center hover:text-base-content"
                    data-testid="remove-card-button"
                    title={gettext("Remove card")}
                  >
                    <.icon name="hero-trash" class="h-4 w-4" />
                    <span class="sr-only">{gettext("Remove card")}</span>
                  </button>
                </div>
              </div>
            </div>
            <div class="text-base-content/40 flex justify-end text-xs">
              <span id="char-count" phx-update="ignore">0</span>/{@card_message_max}
            </div>
          </div>
          <.field_errors field={@form[:card_message]} />
        </fieldset>
      </div>

      <button
        :if={is_nil(@card_line_item)}
        type="button"
        phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#card-drawer")}
        class="text-base-content link-underline-hover-nav inline-flex w-fit cursor-pointer items-center gap-2 text-base"
        data-testid="select-card-button"
      >
        <.icon name="hero-envelope" class="h-4 w-4" />
        {gettext("Select a card")}
      </button>
    </div>
    """
  end

  attr :variants, :list, required: true

  defp card_drawer(assigns) do
    ~H"""
    <.drawer
      id="card-drawer"
      placement="right"
      label="Select a Card"
      class="bg-base-100 w-[80vw] flex h-full flex-col overflow-y-auto p-6 sm:w-[25rem]"
    >
      <div class="flex flex-col gap-6" data-testid="card-drawer">
        <div class="flex flex-row items-center justify-between">
          <h2 class="section-title">{gettext("Select a Card")}</h2>
          <button
            type="button"
            phx-click={JS.exec("phx-hide", to: "#card-drawer")}
            class="h-10 w-10 cursor-pointer"
          >
            <.icon name="hero-x-mark" class="h-6 w-6" />
          </button>
        </div>

        <div
          :for={{size, variants} <- Enum.group_by(@variants, & &1.size)}
          class="flex flex-col gap-3"
        >
          <h3 class="font-semibold">{size_label(size)}</h3>
          <div class="grid grid-cols-2 gap-3">
            <button
              :for={variant <- variants}
              type="button"
              phx-click={
                JS.push("select_card", value: %{"variant-id" => variant.id})
                |> JS.exec("phx-hide", to: "#card-drawer")
              }
              class="border-base-300 flex flex-col items-center gap-1 border p-2 hover:bg-base-200"
              data-testid={"card-option-#{variant.id}"}
            >
              <.image
                src={variant.image_slug}
                alt={variant.product.name}
                width={96}
                height={96}
                sizes="96px"
                class="h-24 w-24 object-cover"
              />
              <span class="text-sm">{variant.product.name}</span>
              <span class="text-base-content/60 text-xs">
                {Edenflowers.Utils.format_money(variant.price)}
              </span>
            </button>
          </div>
        </div>
      </div>
    </.drawer>
    """
  end

  # ==============
  # Event Handlers
  # ==============

  # Form validation & submission

  def handle_event("validate_form", %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  # AddressInputComponent owns the address field's lifecycle independently
  # of the parent form, so submit is the only moment the parent learns the
  # typed value — bridge it into the form params here.
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
         |> push_event("focus-element", %{id: next_section_id})}

      {:error, form} ->
        forward_delivery_address_error(form)
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("save_form", %{"form" => params}, socket) do
    submit_form(socket, params)
  end

  # Step 4 does not save form data — it triggers Stripe payment processing directly.
  def handle_event("save_form_4", _, %{assigns: %{client_secret: nil}} = socket) do
    {:noreply, put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please try again in a moment.")}
  end

  def handle_event("save_form_4", _, socket) do
    case stripe_api().update_payment_intent(socket.assigns.order) do
      {:ok, _payment_intent} ->
        {:noreply, push_event(socket, "stripe:process_payment", %{})}

      {:error, error} ->
        Logger.error("Failed to update payment intent: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, ~t"Payment processing error. Please try again.")}
    end
  end

  # Step navigation
  def handle_event("edit_step", %{"state" => "contact_details"}, socket) do
    Order.return_to_contact_details!(socket.assigns.order, actor: actor(socket))
    {:noreply, scroll_to_state(reload_order(socket), :contact_details)}
  end

  def handle_event("edit_step", %{"state" => "gift_options"}, socket) do
    Order.return_to_gift_options!(socket.assigns.order, actor: actor(socket))
    {:noreply, scroll_to_state(reload_order(socket), :gift_options)}
  end

  def handle_event("edit_step", %{"state" => "delivery"}, socket) do
    Order.return_to_delivery!(socket.assigns.order, actor: actor(socket))
    {:noreply, scroll_to_state(reload_order(socket), :delivery)}
  end

  def handle_event("update_fulfillment_option", %{"form" => %{"fulfillment_option_id" => id}}, socket) do
    Order.update_fulfillment_option!(socket.assigns.order, id, actor: actor(socket))
    {:noreply, reload_order(socket)}
  end

  def handle_event("set_gift", %{"form" => %{"gift" => gift}}, socket) do
    Order.set_gift!(socket.assigns.order, gift, actor: actor(socket))
    {:noreply, reload_order(socket)}
  end

  # Card selection
  def handle_event("select_card", %{"variant-id" => variant_id}, socket) do
    variant = Enum.find(socket.assigns.card_variants, &(&1.id == variant_id))
    order = Order.add_card!(socket.assigns.order, variant.id, actor: actor(socket))
    {:noreply, assign_forms(socket, order)}
  end

  def handle_event("remove_card", _, socket) do
    order = Order.remove_card!(socket.assigns.order, actor: actor(socket))
    {:noreply, assign_forms(socket, order)}
  end

  # Stripe events
  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error("#{message}: #{inspect(details)}")

    {:noreply,
     put_flash(
       socket,
       :error,
       ~t"Payment is temporarily unavailable. Please refresh the page and try again."
     )}
  end

  # ===========
  # Info Events
  # ===========

  def handle_info(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> _}, socket) do
    actor = actor(socket)
    order = Order.get_for_checkout!(socket.assigns.order.id, actor: actor)

    # Cart changed while the customer is on the payment step. The PaymentIntent's
    # amount must follow the new total, otherwise `confirmPayment` would charge
    # the previous amount.
    if order.state == :payment and not is_nil(order.payment_intent_id) do
      {:noreply, sync_payment_intent(assign(socket, order: order), order)}
    else
      {:noreply, assign(socket, order: order)}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:checkout_restarted:" <> _}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_info({:date_selected, date}, socket) do
    form = AshPhoenix.Form.update_params(socket.assigns.form, &Map.put(&1, "fulfillment_date", date))
    {:noreply, assign(socket, form: form)}
  end

  # ==========
  # Components
  # ==========

  attr :state, :atom, required: true
  attr :order, :map, required: true
  slot :inner_block

  def steps(assigns) do
    assigns = assign(assigns, :states, @checkout_states)

    ~H"""
    <ol class="flex flex-col">
      <.checkout_step
        :for={state <- @states}
        state={state}
        current_state={@state}
        order={@order}
      >
        <%= if state == @state do %>
          {render_slot(@inner_block)}
        <% end %>
      </.checkout_step>
    </ol>
    """
  end

  attr :state, :atom, required: true
  attr :current_state, :atom, required: true
  attr :order, :map, required: true
  slot :inner_block

  defp checkout_step(assigns) do
    position_for = state_index(assigns.current_state)
    position = state_index(assigns.state)

    relative =
      cond do
        position < position_for -> :past
        position == position_for -> :current
        true -> :future
      end

    assigns =
      assigns
      |> assign(:relative, relative)
      |> assign(:position, position + 1)
      |> assign(:title, step_title(assigns.state))
      |> assign(:summary, if(relative == :past, do: step_summary(assigns.state, assigns.order)))

    ~H"""
    <li class={["border-base-content/12 py-8 md:py-10", @position > 1 && "border-t"]}>
      <div class="flex items-baseline justify-between gap-4">
        <div class="flex items-baseline gap-3">
          <span
            aria-hidden="true"
            class={["eyebrow tabular-nums", @relative == :current && "text-[var(--color-link-underline)]", @relative != :current && "text-base-content/55"]}
          >
            {String.pad_leading(Integer.to_string(@position), 2, "0")}
          </span>
          <h2 class={["section-title flex items-baseline gap-2", @relative == :past && "text-base-content/70", @relative == :future && "text-base-content/40"]}>
            <span class="sr-only">{step_label(@relative)}: </span>
            <span>{@title}</span>
            <.icon
              :if={@relative == :past}
              name="hero-check-mini"
              class="size-4 text-base-content/70 self-center"
            />
          </h2>
        </div>
        <.link
          :if={@relative == :past}
          phx-click={JS.push("edit_step", value: %{state: @state})}
          class="link-underline-hover-nav shrink-0 text-sm"
        >
          {~t"Edit"}
        </.link>
      </div>

      <p :if={@relative == :past && @summary} class="text-base-content/70 mt-3">
        {@summary}
      </p>

      <div :if={@relative == :current} class="mt-8">
        {render_slot(@inner_block)}
      </div>
    </li>
    """
  end

  defp step_title(:contact_details), do: ~t"Your details"
  defp step_title(:gift_options), do: ~t"Gift options"
  defp step_title(:delivery), do: ~t"Delivery"
  defp step_title(:payment), do: ~t"Payment"

  defp step_label(:past), do: ~t"Completed"
  defp step_label(:current), do: ~t"Current step"
  defp step_label(:future), do: ~t"Upcoming"

  defp step_summary(:contact_details, %{customer_name: name, customer_email: email})
       when is_binary(name) and is_binary(email),
       do: "#{name} · #{email}"

  defp step_summary(:gift_options, %{gift: false}), do: ~t"For me"
  defp step_summary(:gift_options, %{gift: true, recipient_name: name}) when is_binary(name), do: ~t"For #{name}"
  defp step_summary(:gift_options, _), do: nil

  defp step_summary(:delivery, %{fulfillment_method: method, fulfillment_date: date} = order)
       when not is_nil(method) and not is_nil(date) do
    method_label = if method == :delivery, do: ~t"Delivery", else: ~t"Pickup"
    address = if method == :delivery, do: order.delivery_address, else: nil

    [method_label, format_date(date), address]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp step_summary(_, _), do: nil

  defp format_date(%Date{} = date) do
    locale = Localize.get_locale().cldr_locale_id
    Localize.Date.to_string!(date, locale: locale, format: :medium)
  end

  defp format_date(_), do: nil

  # Renders field errors only after the user has interacted with the input,
  # matching Phoenix's `used_input?` convention so we don't flash errors at
  # untouched fields on first render.
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

  attr :rest, :global
  attr :disabled, :boolean, default: false
  slot :inner_block

  defp form_button(assigns) do
    ~H"""
    <button
      {@rest}
      disabled={@disabled}
      type="submit"
      class="btn btn-primary btn-lg mt-2 flex flex-row gap-2 phx-submit-loading:btn-disabled"
    >
      <span>{render_slot(@inner_block)}</span>
      <span class="phx-submit-loading:loading-spinner phx-submit-loading:loading"></span>
    </button>
    """
  end

  # =========
  # Utilities
  # =========

  defp handle_mount_error(socket, log_message, flash_message) do
    Logger.error(log_message)

    {:ok,
     socket
     |> put_flash(:error, flash_message)
     |> push_navigate(to: ~p"/")}
  end

  defp recipient_label(%{gift: true, recipient_name: name}, field) when is_binary(name) and name != "" do
    first_name = name |> String.split() |> List.first()

    case field do
      "address" -> gettext("%{name}'s Address *", name: first_name)
      "phone" -> gettext("%{name}'s Phone Number", name: first_name)
    end
  end

  defp recipient_label(_order, field) do
    case field do
      "address" -> gettext("Address *")
      "phone" -> gettext("Phone Number")
    end
  end

  defp make_form(order, action, params) do
    order
    |> AshPhoenix.Form.for_update(action, params: params)
    |> to_form()
  end

  # Builds the submit-form for the order's current state. Returns nil on the
  # payment state because the payment screen is driven by Stripe Elements
  # (not an Ash form submission).
  defp build_submit_form(order, params \\ %{}) do
    case submit_action_for(order.state) do
      nil -> nil
      action -> make_form(order, action, params)
    end
  end

  # Rebuilds the submit form against the latest order while preserving any
  # unsaved input the customer has typed. The data side has to refresh because
  # some validations read off the order's loaded relationships (e.g. line_items);
  # the params side has to be preserved so selecting a card doesn't wipe values
  # the customer is still editing.
  defp assign_forms(socket, order) do
    form_params = if form = socket.assigns[:form], do: form.params, else: %{}

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
         |> push_event("focus-element", %{id: next_section_id})}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  # When `submit_delivery` fails on the delivery_address field, surface
  # the error inside the address input component so the user sees it next
  # to the field instead of at the form root.
  defp forward_delivery_address_error(form) do
    case form[:delivery_address].errors do
      [error | _] ->
        send_update(EdenflowersWeb.AddressInputComponent,
          id: "address-input",
          error_message: translate_error(error)
        )

      _ ->
        :ok
    end
  end

  defp actor(socket), do: socket.assigns[:current_user]

  defp reload_order(socket) do
    order = Order.get_for_checkout!(socket.assigns.order.id, actor: actor(socket))
    order = ensure_fulfillment_default(order, socket.assigns.fulfillment_options, actor(socket))

    socket
    |> assign_forms(order)
    |> ensure_stripe_for_state(order)
  end

  # When the customer reaches the payment state, lazily create or retrieve
  # the PaymentIntent. Skip if `client_secret` is already cached for the
  # current session — re-running on every reload would burn a Stripe API
  # call per event.
  defp ensure_stripe_for_state(socket, %{state: :payment} = order) do
    if socket.assigns[:client_secret] do
      socket
    else
      setup_stripe(socket, order)
    end
  end

  defp ensure_stripe_for_state(socket, _order), do: socket

  # Persisted (not just visual) so the dependent form-3b renders and the
  # value flows through on submit.
  defp ensure_fulfillment_default(%{state: :delivery, fulfillment_option_id: nil} = order, options, actor) do
    case List.first(options) do
      nil -> order
      %{id: id} -> Order.update_fulfillment_option!(order, id, actor: actor)
    end
  end

  defp ensure_fulfillment_default(order, _options, _actor), do: order

  defp cart_has_items?(%{cart_effectively_empty?: true}), do: {:error, :empty_cart}
  defp cart_has_items?(_order), do: :ok

  defp next_section_id(id, state) when state in @checkout_states do
    "#{id}-section-#{state_index(state) + 1}"
  end

  defp next_section_id(_, _), do: nil

  defp scroll_to_state(socket, state) do
    push_event(socket, "focus-element", %{id: "#{socket.assigns.id}-section-#{state_index(state) + 1}"})
  end

  defp size_label(:small), do: gettext("Small")
  defp size_label(:medium), do: gettext("Medium")
  defp size_label(:large), do: gettext("Large")
  defp size_label(size) when is_atom(size), do: size |> Atom.to_string() |> String.capitalize()
  defp size_label(_), do: ""

  # Stripe utilities
  #
  # We only touch Stripe once the customer is on the payment state. Earlier
  # mounts (or mounts where the LiveView reconnects on a non-payment state)
  # skip the round trip entirely.
  defp maybe_setup_stripe(socket, %{state: :payment} = order), do: setup_stripe(socket, order)
  defp maybe_setup_stripe(socket, _order), do: socket

  defp setup_stripe(socket, %{payment_intent_id: nil} = order) do
    case stripe_api().create_payment_intent(order) do
      {:ok, payment_intent} ->
        case Order.add_payment_intent_id(order, payment_intent.id, actor: actor(socket)) do
          {:ok, order} ->
            socket
            |> assign(order: order)
            |> assign(client_secret: payment_intent.client_secret)

          {:error, reason} ->
            # Persisting the id failed — cancel the orphan intent on Stripe so it
            # doesn't linger in the dashboard. Best-effort; surface a flash either way.
            stripe_api().cancel_payment_intent(payment_intent)

            Logger.error("Failed to persist payment_intent_id for order #{order.id}: #{inspect(reason)}")

            stripe_unavailable(socket)
        end

      {:error, reason} ->
        Logger.error("Failed to create payment intent for order #{order.id}: #{inspect(reason)}")
        stripe_unavailable(socket)
    end
  end

  defp setup_stripe(socket, order) do
    case stripe_api().retrieve_payment_intent(order) do
      {:ok, payment_intent} ->
        assign(socket, client_secret: payment_intent.client_secret)

      {:error, reason} ->
        Logger.error("Failed to retrieve payment intent for order #{order.id}: #{inspect(reason)}")
        stripe_unavailable(socket)
    end
  end

  # Re-sync the existing PaymentIntent's amount with the current order total
  # without changing the client_secret (so the already-mounted Elements UI keeps
  # working).
  defp sync_payment_intent(socket, order) do
    case stripe_api().update_payment_intent(order) do
      {:ok, _payment_intent} ->
        socket

      {:error, reason} ->
        Logger.error("Failed to sync payment intent amount for order #{order.id}: #{inspect(reason)}")

        put_flash(socket, :error, ~t"Cart changed but payment couldn't be updated. Please retry.")
    end
  end

  defp stripe_unavailable(socket) do
    socket
    |> assign(client_secret: nil)
    |> put_flash(:error, ~t"Payment is temporarily unavailable. Please try again in a moment.")
  end
end
