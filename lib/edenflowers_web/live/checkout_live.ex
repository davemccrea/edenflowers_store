defmodule EdenflowersWeb.CheckoutLive do
  use EdenflowersWeb, :live_view

  require Logger
  require Ash.Query

  alias Edenflowers.Store.{Order, FulfillmentOption}
  alias Edenflowers.{Fulfillments, StripeAPI}

  on_mount {EdenflowersWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, %{assigns: %{order: order}} = socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:updated:#{order.id}")
    end

    with {:ok, _line_items} <- cart_has_items?(order),
         {:ok, fulfillment_options} <- Ash.read(FulfillmentOption) do
      {:ok,
       socket
       |> assign(:id, "checkout")
       |> assign(:page_title, gettext("Checkout"))
       |> assign(:fulfillment_options, fulfillment_options)
       |> assign(:order, order)
       |> assign(:form, make_form(order, action_name(:save, order.step)))
       |> assign(:promotional_form, make_form(order, :add_promotion_with_code))
       |> setup_stripe(order)}
    else
      {:error, :empty_cart} ->
        handle_mount_error(socket, "Cart is empty", gettext("Cart is empty"))

      error ->
        Logger.error("Error loading checkout: #{inspect(error)}")
        handle_mount_error(socket, "Error loading checkout", gettext("Error loading checkout"))
    end
  end

  # ======
  # Markup
  # ======

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash}>
      <div class="mt-[calc(var(--header-height)+var(--spacing)*8)] mx-4 mb-24 lg:mx-24 xl:mx-48 2xl:mx-64">
        <div class="flex flex-col gap-12">
          <div class="text-neutral/60 flex flex-row gap-2">
            <.icon name="hero-lock-closed" class="h-4 w-4" />
            <span class="items-center text-xs uppercase">{gettext("Secure Checkout")}</span>
          </div>

          <div class="flex flex-col gap-8 md:flex-row">
            <div id={@id} class="md:w-[60%]" phx-hook="FocusElement">
              <.steps step={@order.step}>
                <section :if={@order.step == 1} id={"#{@id}-section-1"} class="checkout__section">
                  <.form_heading>{gettext("Your Details")}</.form_heading>

                  <.form
                    id={"#{@id}-form-1"}
                    for={@form}
                    phx-change="validate_form_1"
                    phx-submit="save_form_1"
                    class="checkout__form"
                  >
                    <.input label={gettext("Your Name *")} field={@form[:customer_name]} type="text" />
                    <.input label={gettext("Email *")} field={@form[:customer_email]} type="text" />

                    <.form_button>{gettext("Next")}</.form_button>
                  </.form>
                </section>

                <section :if={@order.step == 2} id={"#{@id}-section-2"} class="checkout__section">
                  <.form_heading>{gettext("Gift Options")}</.form_heading>

                  <.form
                    id={"#{@id}-form-2"}
                    for={@form}
                    phx-change="validate_form_2"
                    phx-submit="save_form_2"
                    class="checkout__form"
                  >
                    <.input
                      :let={option}
                      type="radio-card"
                      label={gettext("Recipient *")}
                      field={@form[:gift]}
                      options={[%{name: "❤️ For me", value: "false"}, %{name: "🎁 For somebody else", value: "true"}]}
                      phx-change="update_gift"
                    >
                      {option.name}
                    </.input>

                    <.input
                      hidden={not @order.gift}
                      label={gettext("Recipient Name *")}
                      field={@form[:recipient_name]}
                      type="text"
                    />

                    <fieldset
                      class={[not @order.gift && "hidden"]}
                      id={"#{@id}-field-gift-message"}
                      phx-hook="CharacterCount"
                    >
                      <label class="relative flex flex-col">
                        <span class="mb-1">{gettext("Gift Message")}</span>
                        <textarea
                          id={@form[:gift_message].id}
                          name={@form[:gift_message].name}
                          class="textarea textarea-lg w-full resize-none"
                          maxlength={200}
                          rows={5}
                        >{@form[:gift_message].value}</textarea>
                        <div class="absolute right-2 bottom-1">
                          <span id="char-count" class="text-xs" phx-update="ignore">
                            0/200
                          </span>
                        </div>
                      </label>

                      <.error :for={msg <- Enum.map(@form[:gift_message].errors, &translate_error(&1))}>
                        {msg}
                      </.error>
                    </fieldset>
                    <.form_button>{gettext("Next")}</.form_button>
                  </.form>
                </section>

                <section :if={@order.step == 3} id={"#{@id}-section-3"} class="checkout__section">
                  <.form_heading>{gettext("Delivery Information")}</.form_heading>

                  <.form id={"#{@id}-form-3a"} for={%{}} phx-change="update_fulfillment_option">
                    <.input
                      :let={option}
                      type="radio-card"
                      field={@form[:fulfillment_option_id]}
                      options={Enum.map(@fulfillment_options, fn %{id: id, name: name} -> %{name: name, value: id} end)}
                      label={gettext("Delivery Method *")}
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
                      <%= if @order.fulfillment_option.fulfillment_method == :delivery do %>
                        <.input
                          placeholder={gettext("Stadsgatan 3, 65300 Vasa")}
                          label={gettext("Address *")}
                          field={@form[:delivery_address]}
                          type="text"
                        />

                        <.input
                          label={gettext("Delivery Instructions")}
                          field={@form[:delivery_instructions]}
                          type="text"
                          placeholder={gettext("e.g. Door code 1234, leave at the front door")}
                        />
                      <% end %>

                      <.input
                        label={gettext("Phone Number")}
                        placeholder={gettext("045 1505141")}
                        field={@form[:recipient_phone_number]}
                        type="text"
                      />

                      <fieldset class="flex flex-col">
                        <label class="mb-1">
                          <%= if @order.fulfillment_option.fulfillment_method == :delivery do %>
                            {gettext("Delivery Date *")}
                          <% else %>
                            {gettext("Pickup Date *")}
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
                              class="absolute top-0 right-0 left-0 m-auto h-3 w-3 translate-y-0.5 text-red-400"
                            />
                          </:day_decoration>
                        </.live_component>
                        <.input field={@form[:fulfillment_date]} hidden />
                      </fieldset>

                      <.form_button>{gettext("Next")}</.form_button>
                    </.form>
                  <% end %>
                </section>

                <section :if={@order.step == 4} id={"#{@id}-section-4"} class="checkout__section">
                  <.form_heading>{gettext("Payment")}</.form_heading>

                  <form
                    id={"#{@id}-form-4"}
                    phx-hook="Stripe"
                    phx-submit="save_form_4"
                    data-client-secret={@client_secret}
                    data-order-id={@order.id}
                    data-return-url={url(~p"/checkout/complete/#{@order.id}")}
                    data-stripe-loading={JS.set_attribute({"disabled", "true"}, to: "#payment-button")}
                    data-stripe-ready={JS.remove_attribute("disabled", to: "#payment-button")}
                    class="flex flex-col gap-4"
                  >
                    <div phx-update="ignore" id="payment-element"></div>
                    <div phx-update="ignore" id="stripe-error-message" class="text-error"></div>

                    <.form_button disabled={true} id="payment-button">
                      {gettext("Pay")} {Edenflowers.Utils.format_money(@order.total)}
                    </.form_button>
                  </form>
                </section>
              </.steps>
            </div>

            <div class="md:border-neutral/10 md:border-r" />

            <div class="md:w-[35%] md:sticky md:top-6 md:h-fit md:overflow-y-auto">
              <section class="flex flex-col gap-4 p-1">
                <h2 class="font-serif text-xl">
                  {gettext("Cart")} ({if @order.total_items_in_cart, do: @order.total_items_in_cart, else: 0})
                </h2>

                <.live_component id="checkout-line-items" module={EdenflowersWeb.LineItemsComponent} order={@order} />

                <.form
                  :if={not @order.promotion_applied?}
                  id={"#{@id}-form-promotional"}
                  for={@promotional_form}
                  phx-submit="update_promotional"
                  class="space-y-2"
                >
                  <.input
                    style="button-addon"
                    label={gettext("Promo Code")}
                    field={@promotional_form[:code]}
                    type="text"
                    button_text={gettext("Apply")}
                    placeholder={gettext("Enter promo code")}
                  />
                </.form>

                <div class="border-neutral/5 border-t"></div>

                <div class="flex flex-col gap-2 text-sm">
                  <div class="flex justify-between">
                    <span>{gettext("Delivery")}</span>
                    <%= if Decimal.eq?(@order.fulfillment_amount || 0, 0) do %>
                      {gettext("Free")}
                    <% else %>
                      <span>{Edenflowers.Utils.format_money(@order.fulfillment_amount)}</span>
                    <% end %>
                  </div>

                  <div class="flex justify-between">
                    <div class="flex flex-row gap-2">
                      <span>{gettext("Discount")}</span>
                      <button
                        :if={@order.promotion_applied?}
                        phx-click="clear_promo"
                        class="badge badge-dash badge-neutral badge-sm flex cursor-pointer items-center gap-1"
                      >
                        {@order.promotion.code} <span><.icon name="hero-x-mark" class="flex h-4 w-4" /></span>
                      </button>
                    </div>

                    <%= if @order.promotion_applied? do %>
                      <span class="text-success">- {Edenflowers.Utils.format_money(@order.discount_amount)}</span>
                    <% else %>
                      <span>- {Edenflowers.Utils.format_money(0)}</span>
                    <% end %>
                  </div>
                </div>

                <div class="flex flex-col gap-2">
                  <div class="border-neutral/5 border-t"></div>

                  <div class="flex justify-between font-semibold">
                    <span>{gettext("Total")}</span>
                    <span>{Edenflowers.Utils.format_money(@order.total)}</span>
                  </div>
                </div>
              </section>
            </div>
          </div>
        </div>
      </div>
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

  def handle_event("save_form_" <> step, %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, order} ->
        # Focus on the next form section after successful submission
        next_section_id = get_next_section_id(socket.assigns.id, String.to_integer(step))

        {:noreply,
         socket
         |> assign(order: order)
         |> push_event("focus-element", %{id: next_section_id})}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("save_form_4", _, socket) do
    case StripeAPI.update_payment_intent(socket.assigns.order) do
      {:ok, _payment_intent} ->
        {:noreply, push_event(socket, "stripe:process_payment", %{})}

      {:error, error} ->
        Logger.error("Failed to update payment intent: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, gettext("Payment processing error. Please try again."))}
    end
  end

  # Step navigation
  def handle_event("edit_step_" <> step, _params, %{assigns: %{order: order}} = socket) do
    step = String.to_integer(step)

    order =
      order
      |> Ash.Changeset.for_update(action_name(:edit, step))
      |> Ash.update!()

    {:noreply, assign(socket, order: order)}
  end

  # Order updates
  def handle_event("update_fulfillment_option", %{"form" => %{"fulfillment_option_id" => id}}, socket) do
    actor = socket.assigns[:current_user]
    order = Order.update_fulfillment_option!(socket.assigns.order, id, actor: actor)
    {:noreply, assign(socket, order: order)}
  end

  def handle_event("update_gift", %{"form" => %{"gift" => gift}}, socket) do
    actor = socket.assigns[:current_user]
    order = Order.update_gift!(socket.assigns.order, gift, actor: actor)
    {:noreply, assign(socket, order: order)}
  end

  def handle_event("update_promotional", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.promotional_form, params: params) do
      {:ok, order} ->
        {:noreply, assign(socket, order: order)}

      {:error, promotional_form} ->
        {:noreply, assign(socket, promotional_form: promotional_form)}
    end
  end

  def handle_event("clear_promo", _, socket) do
    actor = socket.assigns[:current_user]
    order = Order.clear_promotion!(socket.assigns.order, actor: actor)
    {:noreply, assign(socket, order: order)}
  end

  # Stripe events
  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error("#{message}: #{inspect(details)}")
    {:noreply, socket}
  end

  # ===========
  # Info Events
  # ===========

  def handle_info({:date_selected, date}, socket) do
    form = AshPhoenix.Form.update_params(socket.assigns.form, &Map.put(&1, "fulfillment_date", date))
    {:noreply, assign(socket, form: form)}
  end

  # Reloads order and rebuilds forms when order is updated via PubSub.
  # Centralizes form synchronization to prevent stale data across all order modifications.
  def handle_info(%Phoenix.Socket.Broadcast{topic: "order:updated:" <> order_id}, socket) do
    actor = socket.assigns[:current_user]
    order = Order.get_for_checkout!(order_id, actor: actor)

    {:noreply,
     socket
     |> assign(order: order)
     |> assign(form: make_form(order, action_name(:save, order.step)))
     |> assign(promotional_form: make_form(order, :add_promotion_with_code))}
  end

  # Redirects to homepage when cart becomes empty.
  # The HandleLineItemChanged hook updates the order, but this handler manages the redirect.
  def handle_info(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> _order_id}, socket) do
    if Enum.empty?(socket.assigns.order.line_items),
      do: {:noreply, push_navigate(socket, to: ~p"/")},
      else: {:noreply, socket}
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
            1 -> gettext("Your Details")
            2 -> gettext("Gift Options")
            3 -> gettext("Delivery Information")
            4 -> gettext("Payment")
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
      <h1 class={"#{if @active, do: "text-neutral", else: "text-neutral/40"} font-serif text-3xl"} {@rest}>
        {render_slot(@inner_block)}
      </h1>
      <button :if={@edit_step} type="button" class="btn btn-ghost text-neutral/40" phx-click={"edit_step_#{@edit_step}"}>
        {gettext("Edit")}
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

  defp action_name(action, step) when is_atom(action) and is_integer(step) do
    String.to_atom("#{action}_step_#{step}")
  end

  defp make_form(order, action) do
    order
    |> AshPhoenix.Form.for_update(action)
    |> to_form()
  end

  defp cart_has_items?(%{line_items: []}), do: {:error, :empty_cart}
  defp cart_has_items?(%{line_items: line_items}), do: {:ok, line_items}

  defp get_next_section_id(id, 1), do: "#{id}-form-2"
  defp get_next_section_id(id, 2), do: "#{id}-form-3a"
  defp get_next_section_id(id, 3), do: "#{id}-form-4"
  defp get_next_section_id(_, _), do: nil

  # Stripe utilities
  defp setup_stripe(socket, %{payment_intent_id: nil} = order) do
    {:ok, payment_intent} = StripeAPI.create_payment_intent(order)
    actor = socket.assigns[:current_user]
    order = Order.add_payment_intent_id!(order, payment_intent.id, actor: actor)

    socket
    |> assign(order: order)
    |> assign(client_secret: payment_intent.client_secret)
  end

  defp setup_stripe(socket, order) do
    {:ok, payment_intent} = StripeAPI.retrieve_payment_intent(order)
    assign(socket, client_secret: payment_intent.client_secret)
  end
end
