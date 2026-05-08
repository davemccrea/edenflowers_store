defmodule EdenflowersWeb.CheckoutLive do
  use EdenflowersWeb, :live_view

  require Logger

  alias Edenflowers.Store.{Order, FulfillmentOption, ProductVariant, ProductVariantSize}
  alias Edenflowers.Fulfillments

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  defp stripe_api, do: Application.get_env(:edenflowers, :stripe_api, Edenflowers.StripeAPI)
  defp stripe_publishable_key, do: Application.get_env(:edenflowers, :stripe_publishable_key)

  def mount(_params, _session, %{assigns: %{order: order}} = socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "line_item:changed:#{order.id}")
    end

    with :ok <- cart_has_items?(order),
         {:ok, fulfillment_options} <- FulfillmentOption.list() do
      fulfillment_options = sort_fulfillment_options(fulfillment_options)
      order = ensure_fulfillment_default(order, fulfillment_options, socket.assigns[:current_user])
      card_variants = ProductVariant.for_card_drawer!()

      {:ok,
       socket
       |> assign(:id, "checkout")
       |> assign(:page_title, ~t"Checkout")
       |> assign(:fulfillment_options, fulfillment_options)
       |> assign(:card_variants, card_variants)
       |> assign(:order, order)
       |> assign(:form, make_form(order, action_name(:save, order.step)))
       |> assign(:promo_code_form, make_form(order, :add_promotion_with_code))
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
      <div class="mt-[calc(var(--header-height)+var(--spacing)*8)] mx-4 mb-24 lg:mx-24 xl:mx-48 2xl:mx-64">
        <div class="flex flex-col gap-12">
          <div class="flex flex-col gap-8 md:flex-row">
            <div id={@id} class="md:w-[60%]" phx-hook="FocusElement">
              <.steps step={@order.step}>
                <section
                  :if={@order.step == 1}
                  id={"#{@id}-section-1"}
                  class="checkout__section"
                  data-testid="checkout-step-1"
                >
                  <.form_heading>{~t"Your Details"}</.form_heading>

                  <.form
                    id={"#{@id}-form-1"}
                    for={@form}
                    phx-change="validate_form_1"
                    phx-submit="save_form_1"
                    class="checkout__form"
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
                      type="text"
                      data-testid="customer-email-input"
                    />

                    <.form_button data-testid="step-1-next-button">{~t"Next"}</.form_button>
                  </.form>
                </section>

                <section
                  :if={@order.step == 2}
                  id={"#{@id}-section-2"}
                  class="checkout__section"
                  data-testid="checkout-step-2"
                >
                  <.form_heading>{~t"Gift Options"}</.form_heading>

                  <.form
                    id={"#{@id}-form-2"}
                    for={@form}
                    phx-change="validate_form_2"
                    phx-submit="save_form_2"
                    class="checkout__form"
                    data-testid="checkout-form-2"
                  >
                    <.input
                      :let={option}
                      type="radio-card"
                      label={~t"Recipient *"}
                      field={@form[:gift]}
                      options={[%{name: "❤️ For me", value: "false"}, %{name: "🎁 For somebody else", value: "true"}]}
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

                    <% card_line_item = Enum.find(@order.line_items, & &1.is_card) %>
                    <% card_message_max =
                      if card_line_item, do: ProductVariantSize.max_message_length(card_line_item.card_size) %>

                    <div :if={@order.gift} class="flex flex-col gap-4" data-testid="card-selection">
                      <div :if={card_line_item} data-testid="card-preview">
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
                                maxlength={card_message_max}
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
                                    <img
                                      src={
                                        card_line_item.product_image_slug
                                        |> Imgproxy.new()
                                        |> Imgproxy.resize(160, 160, type: "fill")
                                        |> to_string()
                                      }
                                      alt={card_line_item.product_name}
                                      class="h-20 w-20 object-cover transition-opacity hover:opacity-70"
                                    />
                                  </button>
                                  <button
                                    type="button"
                                    phx-click="remove_card"
                                    class="btn btn-circle btn-ghost bg-base-200 absolute -top-2 -right-2 h-7 min-h-0 w-7"
                                    data-testid="remove-card-button"
                                    title={gettext("Remove card")}
                                  >
                                    <.icon name="hero-trash" class="text-error h-4 w-4" />
                                    <span class="sr-only">{gettext("Remove card")}</span>
                                  </button>
                                </div>
                              </div>
                            </div>
                            <div class="text-base-content/40 flex justify-end text-xs">
                              <span id="char-count" phx-update="ignore">0</span>/{card_message_max}
                            </div>
                          </div>
                          <.error :for={
                            msg <-
                              if Phoenix.Component.used_input?(@form[:card_message]),
                                do: Enum.map(@form[:card_message].errors, &translate_error/1),
                                else: []
                          }>
                            {msg}
                          </.error>
                        </fieldset>
                      </div>

                      <button
                        :if={is_nil(card_line_item)}
                        type="button"
                        phx-click={JS.push_focus() |> JS.exec("phx-show", to: "#card-drawer")}
                        class="btn btn-dash w-full"
                        data-testid="select-card-button"
                      >
                        <.icon name="hero-gift" class="h-4 w-4" />
                        {gettext("Add a card")}
                      </button>
                    </div>

                    <.form_button>{gettext("Next")}</.form_button>
                  </.form>
                </section>

                <section :if={@order.step == 3} id={"#{@id}-section-3"} class="checkout__section">
                  <.form_heading>{~t"Delivery Information"}</.form_heading>

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
                      phx-change="validate_form_3"
                      phx-submit="save_form_3"
                      class="checkout__form"
                    >
                      <.live_component
                        :if={@order.fulfillment_method == :delivery}
                        id="address-input"
                        module={EdenflowersWeb.AddressInputComponent}
                        order={@order}
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
                        type="text"
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
                          on_select={fn date -> send(self(), {:date_selected, date}) end}
                          date_callback={
                            fn date ->
                              {_, state} = Fulfillments.fulfill_on_date(@order.fulfillment_option, date)
                              state
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
                        <.error :for={
                          msg <-
                            if(Phoenix.Component.used_input?(@form[:fulfillment_date]),
                              do: Enum.map(@form[:fulfillment_date].errors, &translate_error(&1)),
                              else: []
                            )
                        }>
                          {msg}
                        </.error>
                        <.input field={@form[:fulfillment_date]} hidden />
                      </fieldset>

                      <.form_button>{~t"Next"}</.form_button>
                    </.form>
                  <% end %>
                </section>

                <section :if={@order.step == 4} id={"#{@id}-section-4"} class="checkout__section">
                  <.form_heading>{~t"Payment"}</.form_heading>

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
                    <div phx-update="ignore" id="express-checkout-container" class="flex flex-col gap-4">
                      <div id="express-checkout-element"></div>
                      <div id="express-checkout-divider" class="divider">{~t"Or pay with card"}</div>
                    </div>
                    <div phx-update="ignore" id="payment-element"></div>
                    <div phx-update="ignore" id="stripe-error-message" class="text-error"></div>

                    <.form_button disabled={true} id="payment-button">
                      {~t"Pay"} {Edenflowers.Utils.format_money(@order.total)}
                    </.form_button>
                  </form>

                  <p :if={!@client_secret} class="text-error" data-testid="stripe-unavailable">
                    {~t"Payment is temporarily unavailable. Please try again in a moment."}
                  </p>
                </section>
              </.steps>
            </div>

            <div class="md:border-neutral/20 md:border-r" />

            <div class="md:w-[35%] md:sticky md:top-6 md:h-fit md:overflow-y-auto">
              <section class="flex flex-col gap-4 p-1" data-testid="cart-section">
                <h2 class="card-title" data-testid="cart-heading">
                  {~t"Cart"} ({if @order.total_items_in_cart, do: @order.total_items_in_cart, else: 0})
                </h2>

                <.live_component id="checkout-line-items" module={EdenflowersWeb.LineItemsComponent} order={@order} />

                <.form
                  :if={not @order.promotion_applied?}
                  id={"#{@id}-form-promotional"}
                  for={@promo_code_form}
                  phx-submit="update_promotional"
                  class="space-y-2"
                  data-testid="promo-code-form"
                >
                  <.input
                    style="button-addon"
                    label={~t"Promo Code"}
                    field={@promo_code_form[:code]}
                    type="text"
                    button_text={~t"Apply"}
                    placeholder={~t"Enter promo code"}
                    data-testid="promo-code-input"
                  />
                </.form>

                <div class="border-neutral/5 border-t"></div>

                <div class="flex flex-col gap-2 text-sm">
                  <div :if={@order.step >= 4} class="flex justify-between" data-testid="delivery-cost">
                    <span>{~t"Delivery"}</span>
                    <%= cond do %>
                      <% is_nil(@order.fulfillment_amount) -> %>
                        <span>—</span>
                      <% Decimal.eq?(@order.fulfillment_amount, 0) -> %>
                        {~t"Free"}
                      <% true -> %>
                        <span>{Edenflowers.Utils.format_money(@order.fulfillment_amount)}</span>
                    <% end %>
                  </div>

                  <div class="flex justify-between" data-testid="discount-section">
                    <div class="flex flex-row gap-2">
                      <span>{~t"Discount"}</span>
                      <button
                        :if={@order.promotion_applied?}
                        phx-click="clear_promo"
                        class="badge badge-dash badge-neutral badge-sm flex cursor-pointer items-center gap-1"
                        data-testid="promo-code-badge"
                      >
                        {@order.promotion.code} <span><.icon name="hero-x-mark" class="flex h-4 w-4" /></span>
                      </button>
                    </div>

                    <%= if @order.promotion_applied? do %>
                      <span class="text-success" data-testid="discount-amount">
                        - {Edenflowers.Utils.format_money(@order.discount_amount)}
                      </span>
                    <% else %>
                      <span data-testid="discount-amount">- {Edenflowers.Utils.format_money(0)}</span>
                    <% end %>
                  </div>
                </div>

                <div class="flex flex-col gap-2">
                  <div class="border-neutral/5 border-t"></div>

                  <div class="flex justify-between font-semibold" data-testid="order-total">
                    <span>{~t"Total"}</span>
                    <span data-testid="total-amount">{Edenflowers.Utils.format_money(@order.total)}</span>
                  </div>
                </div>
              </section>
            </div>
          </div>
        </div>
      </div>

      <.drawer
        id="card-drawer"
        placement="right"
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
            :for={{size, variants} <- Enum.group_by(@card_variants, & &1.size)}
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
                <img
                  src={
                    variant.image_slug
                    |> Imgproxy.new()
                    |> Imgproxy.resize(200, 200, type: "fill")
                    |> to_string()
                  }
                  alt={variant.product.name}
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
    </Layouts.app>
    """
  end

  # ==============
  # Event Handlers
  # ==============

  # Form validation & submission

  def handle_event("validate_form_" <> _step, %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
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

  # AddressInputComponent owns the address field's lifecycle independently
  # of the parent form, so submit is the only moment the parent learns the
  # typed value — bridge it into the form params here.
  def handle_event("save_form_3", %{"form" => params} = all_params, socket) do
    params =
      case all_params do
        %{"delivery_address" => address} -> Map.put(params, "delivery_address", address)
        _ -> params
      end

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _order} ->
        next_section_id = get_next_section_id(socket.assigns.id, 3)

        {:noreply,
         socket
         |> reload_order()
         |> push_event("focus-element", %{id: next_section_id})}

      {:error, form} ->
        forward_delivery_address_error(form)
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("save_form_" <> step, %{"form" => params}, socket) do
    submit_form(socket, String.to_integer(step), params)
  end

  # Step navigation
  def handle_event("edit_step_3", _params, socket) do
    Order.edit_step_3!(socket.assigns.order, actor: actor(socket))
    {:noreply, scroll_to_step(reload_order(socket), 3)}
  end

  def handle_event("edit_step_1", _params, socket) do
    Order.edit_step_1!(socket.assigns.order, actor: actor(socket))
    {:noreply, scroll_to_step(reload_order(socket), 1)}
  end

  def handle_event("edit_step_2", _params, socket) do
    Order.edit_step_2!(socket.assigns.order, actor: actor(socket))
    {:noreply, scroll_to_step(reload_order(socket), 2)}
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

  def handle_event("update_promotional", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.promo_code_form, params: params) do
      {:ok, order} ->
        {:noreply, assign_forms(socket, order)}

      {:error, promo_code_form} ->
        {:noreply, assign(socket, promo_code_form: promo_code_form)}
    end
  end

  def handle_event("clear_promo", _, socket) do
    order = Order.clear_promotion!(socket.assigns.order, actor: actor(socket))
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

    cond do
      order.cart_effectively_empty? ->
        Order.restart_checkout!(order, actor: actor)
        {:noreply, push_navigate(socket, to: ~p"/")}

      # Cart changed while the customer is on the payment step. The PaymentIntent's
      # amount must follow the new total, otherwise `confirmPayment` would charge
      # the previous amount.
      order.step == 4 and not is_nil(order.payment_intent_id) ->
        {:noreply, sync_payment_intent(assign(socket, order: order), order)}

      true ->
        {:noreply, assign(socket, order: order)}
    end
  end

  def handle_info({:date_selected, date}, socket) do
    form = AshPhoenix.Form.update_params(socket.assigns.form, &Map.put(&1, "fulfillment_date", date))
    {:noreply, assign(socket, form: form)}
  end

  # ==========
  # Components
  # ==========

  attr :step, :integer, required: true
  slot :inner_block

  def steps(assigns) do
    assigns =
      assign(assigns,
        step_title: fn n ->
          case n do
            1 -> ~t"Your Details"
            2 -> ~t"Gift Options"
            3 -> ~t"Delivery Information"
            4 -> ~t"Payment"
          end
        end
      )

    ~H"""
    <div :if={@step > 1} class="mb-4 space-y-4">
      <.form_heading :for={n <- 1..(@step - 1)} active={false} edit_step={n}>{@step_title.(n)}</.form_heading>
    </div>

    {render_slot(@inner_block)}

    <div :if={@step < 4} class="mb-4 space-y-4">
      <.form_heading :for={n <- (@step + 1)..4} active={false}>{@step_title.(n)}</.form_heading>
    </div>
    """
  end

  slot :inner_block
  attr :active, :boolean, default: true
  attr :edit_step, :integer, default: nil
  attr :rest, :global

  defp form_heading(assigns) do
    ~H"""
    <div class="flex flex-row items-center justify-between">
      <h1 class={["section-title", if(@active, do: "text-base-content", else: "text-base-content/40")]} {@rest}>
        {render_slot(@inner_block)}
      </h1>
      <button
        :if={@edit_step}
        type="button"
        class="btn btn-ghost text-base-content/40"
        phx-click={"edit_step_#{@edit_step}"}
      >
        {~t"Edit"}
      </button>
    </div>
    """
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

  defp action_name(action, step) when is_atom(action) and is_integer(step) do
    String.to_atom("#{action}_step_#{step}")
  end

  defp make_form(order, action, params \\ %{}) do
    order
    |> AshPhoenix.Form.for_update(action, params: params)
    |> to_form()
  end

  # Rebuilds both forms against the latest order while preserving any unsaved
  # input the customer has typed. The data side has to refresh because some
  # validations read off the order's loaded relationships (e.g. line_items);
  # the params side has to be preserved so applying a promo or selecting a
  # card doesn't wipe values the customer is still editing.
  defp assign_forms(socket, order) do
    form_params = (socket.assigns[:form] && socket.assigns.form.params) || %{}

    promo_params =
      (socket.assigns[:promo_code_form] && socket.assigns.promo_code_form.params) || %{}

    socket
    |> assign(order: order)
    |> assign(form: make_form(order, action_name(:save, order.step), form_params))
    |> assign(promo_code_form: make_form(order, :add_promotion_with_code, promo_params))
  end

  defp submit_form(socket, step, params) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _order} ->
        next_section_id = get_next_section_id(socket.assigns.id, step)

        {:noreply,
         socket
         |> reload_order()
         |> push_event("focus-element", %{id: next_section_id})}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  # When `save_step_3` fails on the delivery_address field, surface the
  # error inside the address input component so the user sees it next to
  # the field instead of at the form root.
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
    |> ensure_stripe_for_step(order)
  end

  # If the customer just reached step 4, lazily create or retrieve the
  # PaymentIntent. Skip if `client_secret` is already cached for the current
  # session — re-running on every reload would burn a Stripe API call per
  # event.
  defp ensure_stripe_for_step(socket, %{step: 4} = order) do
    if socket.assigns[:client_secret] do
      socket
    else
      setup_stripe(socket, order)
    end
  end

  defp ensure_stripe_for_step(socket, _order), do: socket

  # Persisted (not just visual) so the dependent form-3b renders and the
  # value flows through on submit. Keys off fulfillment_method so the default
  # survives option renames/translations.
  defp ensure_fulfillment_default(%{step: 3, fulfillment_option_id: nil} = order, options, actor) do
    case default_fulfillment_option_id(options) do
      nil -> order
      id -> Order.update_fulfillment_option!(order, id, actor: actor)
    end
  end

  defp ensure_fulfillment_default(order, _options, _actor), do: order

  defp default_fulfillment_option_id(options) do
    delivery = Enum.find(options, &(&1.fulfillment_method == :delivery))
    fallback = List.first(options)

    case delivery || fallback do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp sort_fulfillment_options(options) do
    Enum.sort_by(options, fn
      %{fulfillment_method: :delivery} -> 0
      %{fulfillment_method: :pickup} -> 1
      _ -> 2
    end)
  end

  defp cart_has_items?(%{cart_effectively_empty?: true}), do: {:error, :empty_cart}
  defp cart_has_items?(_order), do: :ok

  defp get_next_section_id(id, 1), do: "#{id}-section-2"
  defp get_next_section_id(id, 2), do: "#{id}-section-3"
  defp get_next_section_id(id, 3), do: "#{id}-section-4"
  defp get_next_section_id(_, _), do: nil

  defp scroll_to_step(socket, step) do
    push_event(socket, "focus-element", %{id: "#{socket.assigns.id}-section-#{step}"})
  end

  defp size_label(:small), do: gettext("Small")
  defp size_label(:medium), do: gettext("Medium")
  defp size_label(:large), do: gettext("Large")
  defp size_label(size) when is_atom(size), do: size |> Atom.to_string() |> String.capitalize()
  defp size_label(_), do: ""

  # Stripe utilities
  #
  # We only touch Stripe once the customer is on step 4. Earlier mounts (or
  # mounts where the LiveView reconnects on a non-payment step) skip the round
  # trip entirely.
  defp maybe_setup_stripe(socket, %{step: 4} = order), do: setup_stripe(socket, order)
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
