defmodule EdenflowersWeb.CheckoutLive do
  use EdenflowersWeb, :live_view

  require Logger
  require Ash.Query

  alias Edenflowers.Store.{Order, LineItem, FulfillmentOption, Promotion}
  alias Edenflowers.{HereAPI, Fulfillments}

  def mount(_params, %{"order_id" => order_id}, socket) do
    with {:ok, order} <- Order.get_order_for_checkout(order_id, load: order_load_statement()),
         {:ok, _line_items} <- cart_has_items?(order),
         {:ok, fulfillment_options} <- Ash.read(FulfillmentOption) do
      form =
        order
        |> AshPhoenix.Form.for_update(create_step_action_name(:save, order.step))
        |> to_form()

      {:ok,
       socket
       |> assign(:id, "checkout")
       |> assign(:page_title, "Checkout")
       |> assign(fulfillment_options: fulfillment_options)
       |> assign(order: order)
       |> assign(form: form)
       |> assign(errors: %{delivery_address: nil})
       |> assign(promo_form: %{})
       |> setup_payment_intent(order)
       |> set_delivery_fields_visibility(order.fulfillment_option_id)}
    else
      {:error, :empty_cart} ->
        Logger.error("Cart is empty")

        {:ok,
         socket
         |> put_flash(:error, "Cart is empty")
         |> push_navigate(to: ~p"/")}

      error ->
        Logger.error("Error loading checkout: #{inspect(error)}")

        {:ok,
         socket
         |> put_flash(:error, "Error loading checkout")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp order_load_statement do
    [
      :total_items_in_cart,
      :promotion_applied?,
      :discount_amount,
      :total,
      :tax_amount,
      :line_items,
      :promotion
    ]
  end

  defp cart_has_items?(%{line_items: []}), do: {:error, :empty_cart}
  defp cart_has_items?(%{line_items: line_items}), do: {:ok, line_items}

  # ╔════════╗
  # ║ Markup ║
  # ╚════════╝

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mt-[calc(var(--header-height)+var(--spacing)*8)] mx-4 mb-24 lg:mx-24 xl:mx-48 2xl:mx-64">
        <div class="flex flex-col gap-12">
          <div class="text-neutral/60 flex flex-row gap-2">
            <.icon name="hero-lock-closed" class="h-4 w-4" />
            <span class="items-center text-xs uppercase">{gettext("Secure Checkout")}</span>
          </div>

          <div class="flex flex-col gap-8 md:flex-row">
            <div id={@id} class="md:w-[60%]">
              <.checkout_step_wrapper step={@order.step}>
                <%!-- Your Details --%>
                <section :if={@order.step == 1} id={"#{@id}-section-1"} class="checkout__section">
                  <.form_heading>{gettext("Your Details")}</.form_heading>

                  <.form
                    id="checkout-form-1"
                    for={@form}
                    phx-change="validate_form_1"
                    phx-submit="save_form_1"
                    class="checkout__form"
                  >
                    <.input label={gettext("Name")} field={@form[:customer_name]} type="text" />
                    <.input label={gettext("Email")} field={@form[:customer_email]} type="text" />

                    <.form_button>Next</.form_button>
                  </.form>
                </section>

                <%!-- Gift Options --%>
                <section :if={@order.step == 2} id={"#{@id}-section-2"} class="checkout__section">
                  <.form_heading>{gettext("Gift Options")}</.form_heading>

                  <.form
                    :if={@order.step == 2}
                    id="checkout-form-2"
                    for={@form}
                    phx-change="validate_form_2"
                    phx-submit="save_form_2"
                    class="checkout__form"
                  >
                    <fieldset id="gift-message-fieldset" phx-hook="CharacterCount">
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
                          <span id="char-count" class="text-xs" id="gift-message-char-count" phx-update="ignore">
                            0/200
                          </span>
                        </div>
                      </label>

                      <.error :for={msg <- Enum.map(@form[:gift_message].errors, &translate_error(&1))}>
                        {gettext("Gift Message")} {msg}
                      </.error>
                    </fieldset>

                    <.form_button>Next</.form_button>
                  </.form>
                </section>

                <%!-- Delivery Information --%>
                <section :if={@order.step == 3} id={"#{@id}-section-3"} class="checkout__section">
                  <.form_heading>{gettext("Delivery Information")}</.form_heading>

                  <.form
                    id="checkout-form-3"
                    for={@form}
                    phx-change="validate_form_3"
                    phx-submit="save_form_3"
                    class="checkout__form"
                  >
                    <.input
                      prompt={gettext("Select a delivery method")}
                      label={gettext("Delivery Method")}
                      field={@form[:fulfillment_option_id]}
                      options={format_options_for_select(@fulfillment_options)}
                      type="select"
                    />

                    <.input
                      label={gettext("Phone Number")}
                      placeholder="045 1505141"
                      field={@form[:recipient_phone_number]}
                      type="text"
                    />

                    <div id="delivery-fields" class={"#{not @show_delivery_inputs && "hidden"} flex flex-col space-y-4"}>
                      <div>
                        <.input
                          placeholder="Stadsgatan 3, 65300 Vasa"
                          label="Address *"
                          field={@form[:delivery_address]}
                          type="text"
                        />
                        <.error :if={@errors[:delivery_address]}>{@errors[:delivery_address]}</.error>
                      </div>

                      <.input label="Delivery Instructions" field={@form[:delivery_instructions]} type="text" />
                    </div>

                    <fieldset>
                      <label class="flex flex-col">
                        <span class="mb-1">{gettext("Delivery Date")}</span>
                        <div class="disable-dbl-tap-zoom max-w-xs">
                          <.live_component
                            id="calendar"
                            hidden_input_id="form_fulfillment_date"
                            hidden_input_name="form[fulfillment_date]"
                            selected_date={@form[:fulfillment_date].value}
                            module={EdenflowersWeb.CalendarComponent}
                            date_callback={
                              fn date ->
                                fulfillment_option_id = Phoenix.HTML.Form.input_value(@form, :fulfillment_option_id)
                                fulfillment_option = Enum.find(@fulfillment_options, &(&1.id == fulfillment_option_id))
                                {_, state} = Fulfillments.fulfill_on_date(fulfillment_option, date)
                                state
                              end
                            }
                          >
                          </.live_component>
                        </div>
                      </label>
                    </fieldset>

                    <.form_button>Next</.form_button>
                  </.form>
                </section>

                <%!-- Payment --%>
                <section :if={@order.step == 4} id={"#{@id}-section-4"} class="checkout__section">
                  <.form_heading>{gettext("Payment")}</.form_heading>

                  <form
                    id="stripe"
                    phx-hook="Stripe"
                    phx-update="ignore"
                    data-client-secret={@stripe_client_secret}
                    data-return-url={"http://localhost:4000/checkout/complete/#{@order.id}"}
                    class="flex flex-col gap-4"
                  >
                    <div id="payment-element"></div>
                    <.form_button>
                      {gettext("Pay")} {Edenflowers.Utils.format_money(@order.total)}
                    </.form_button>
                  </form>
                </section>
              </.checkout_step_wrapper>
            </div>

            <div class="md:border-neutral/10 md:border-r"></div>

            <div class="md:w-[35%] md:sticky md:top-6 md:h-fit md:overflow-y-auto">
              <section class="flex flex-col gap-4 p-1">
                <h2 class="font-serif text-xl">
                  {gettext("Cart")} ({if @order.total_items_in_cart, do: @order.total_items_in_cart, else: 0})
                </h2>

                <ul class="flex flex-col gap-2">
                  <li :for={line_item <- @order.line_items} class="flex flex-row gap-4 text-sm">
                    <img
                      class="h-18 w-18 rounded"
                      src={line_item.product_image_slug}
                      alt={"Image of #{line_item.product_name}"}
                    />

                    <div class="flex flex-1 flex-row justify-between">
                      <div class="flex flex-col gap-2">
                        <span>{line_item.product_name}</span>
                        <.increment_decrement resource="line_item" resource_id={line_item.id} count={line_item.quantity} />
                      </div>
                      <div class="flex flex-col items-end gap-2">
                        <span>{Edenflowers.Utils.format_money(line_item.line_subtotal)}</span>
                        <button
                          type="button"
                          id={"remove-item-#{line_item.id}"}
                          phx-hook="DisableButton"
                          class="btn btn-square btn-ghost btn-xs"
                          phx-click="remove_item"
                          phx-value-id={line_item.id}
                          aria-label={gettext("Remove item")}
                        >
                          <.icon name="hero-trash" class="text-error h-4 w-4" />
                        </button>
                      </div>
                    </div>
                  </li>
                </ul>

                <.form :if={not @order.promotion_applied?} for={@promo_form} phx-submit="apply_promo" class="space-y-2">
                  <fieldset class="join w-full">
                    <label class="input join-item w-full">
                      <input name="code" value={@promo_form["code"]} type="text" placeholder="Enter promo code" required />
                    </label>
                    <button class="btn btn-primary join-item z-50">{gettext("Apply")}</button>
                  </fieldset>

                  <.error :if={@errors[:promo_code]}>{@errors[:promo_code]}</.error>
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
                        class="badge badge-dash badge-neutral badge-sm cursor-pointer"
                      >
                        {@order.promotion.code}
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

  # ╔════════════╗
  # ║ Components ║
  # ╚════════════╝

  slot :inner_block
  attr :step, :integer, required: true

  def checkout_step_wrapper(assigns) do
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
        Edit
      </button>
    </div>
    """
  end

  slot :inner_block
  attr :disabled, :boolean
  attr :rest, :global

  defp form_button(assigns) do
    ~H"""
    <button {@rest} type="submit" class="btn btn-primary btn-lg mt-2 flex flex-row gap-2">
      <span>{render_slot(@inner_block)}</span>
    </button>
    """
  end

  # ╔════════════════╗
  # ║ Event Handlers ║
  # ╚════════════════╝

  def handle_event("validate_form_3", %{"form" => params}, socket) do
    fulfillment_option_id = Map.get(params, "fulfillment_option_id")
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {:noreply,
     socket
     |> validate_delivery_address(params)
     |> set_delivery_fields_visibility(fulfillment_option_id)
     |> assign(form: form)}
  end

  def handle_event("validate_form_" <> _step, %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save_form_3", %{"form" => %{"fulfillment_option_id" => id} = params}, socket) do
    fulfillment_option = Enum.find(socket.assigns.fulfillment_options, &(&1.id == id))
    {:noreply, handle_fulfillment_method(socket, params, fulfillment_option)}
  end

  def handle_event("save_form_" <> _step, %{"form" => params}, socket) do
    {:noreply, submit(socket, params)}
  end

  def handle_event("edit_step_" <> step, _params, %{assigns: %{order: order}} = socket) do
    step = String.to_integer(step)

    order =
      order
      |> Ash.Changeset.for_update(create_step_action_name(:edit, step))
      |> Ash.update!(load: order_load_statement())

    form =
      order
      |> AshPhoenix.Form.for_update(create_step_action_name(:save, order.step))
      |> to_form()

    {:noreply,
     socket
     |> assign(order: order)
     |> assign(form: form)}
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    socket.assigns.order.line_items
    |> Enum.find(&(&1.id == id))
    |> LineItem.remove_item()

    order = Order.get_order_for_checkout!(socket.assigns.order.id, load: order_load_statement())

    {:noreply,
     socket
     |> assign(order: order)
     |> update_payment_intent(order)}
  end

  def handle_event("increment_line_item", %{"id" => id}, socket) do
    socket.assigns.order.line_items
    |> Enum.find(&(&1.id == id))
    |> LineItem.increment_quantity()

    order = Order.get_order_for_checkout!(socket.assigns.order.id, load: order_load_statement())

    {:noreply,
     socket
     |> assign(order: order)
     |> update_payment_intent(order)}
  end

  def handle_event("decrement_line_item", %{"id" => id}, socket) do
    socket.assigns.order.line_items
    |> Enum.find(&(&1.id == id))
    |> LineItem.decrement_quantity()

    order = Order.get_order_for_checkout!(socket.assigns.order.id, load: order_load_statement())

    {:noreply,
     socket
     |> assign(order: order)
     |> update_payment_intent(order)}
  end

  def handle_event("apply_promo", %{"code" => code}, socket) do
    promo_form = %{"code" => ""}

    case Promotion.get_by_code(code) do
      {:ok, promotion} ->
        order = Order.add_promotion!(socket.assigns.order, promotion.id, load: order_load_statement())

        {:noreply,
         socket
         |> assign(order: order)
         |> update_payment_intent(order)
         |> add_field_error(:promo_code, nil)
         |> assign(promo_form: promo_form)}

      _ ->
        {:noreply,
         socket
         |> add_field_error(:promo_code, gettext("Not found"))
         |> assign(promo_form: promo_form)}
    end
  end

  def handle_event("clear_promo", _, socket) do
    order = Order.clear_promotion!(socket.assigns.order, load: order_load_statement())

    {:noreply,
     socket
     |> assign(order: order)
     |> update_payment_intent(order)}
  end

  # ╔══════════════╗
  # ║ Form Helpers ║
  # ╚══════════════╝

  defp submit(socket, params) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params, action_opts: [load: order_load_statement()]) do
      {:ok, order} ->
        form =
          order
          |> AshPhoenix.Form.for_update(create_step_action_name(:save, order.step))
          |> to_form()

        socket
        |> assign(order: order)
        |> assign(form: form)
        |> update_payment_intent(order)

      {:error, form} ->
        assign(socket, form: form)
    end
  end

  defp handle_fulfillment_method(socket, params, %{fulfillment_method: :delivery} = fulfillment_option) do
    with {:ok, delivery_address} <- ensure_valid_delivery_address(socket, params),
         {:ok, {calculated_address, position, here_id}} <- HereAPI.get_address(delivery_address),
         {:ok, distance} <- HereAPI.get_distance(position),
         {:ok, fulfillment_amount} <- Fulfillments.calculate_price(fulfillment_option, distance) do
      params =
        Map.merge(params, %{
          fulfillment_amount: fulfillment_amount,
          calculated_address: calculated_address,
          here_id: here_id,
          distance: distance,
          position: position
        })

      submit(socket, params)
    else
      {:error, {_error, error_msg}} ->
        add_field_error(socket, :delivery_address, error_msg)
    end
  end

  defp handle_fulfillment_method(socket, params, %{fulfillment_method: :pickup} = fulfillment_option) do
    {:ok, fulfillment_amount} = Fulfillments.calculate_price(fulfillment_option)

    # Note: using string keys below because forms use string keys
    params =
      Map.merge(params, %{
        "fulfillment_amount" => fulfillment_amount,
        "delivery_address" => nil,
        "calculated_address" => nil,
        "here_id" => nil,
        "distance" => nil,
        "position" => nil
      })

    submit(socket, params)
  end

  defp set_delivery_fields_visibility(socket, fulfillment_id) do
    fulfillment_method =
      socket.assigns.fulfillment_options
      |> Enum.find(&(&1.id == fulfillment_id))
      |> Map.get(:fulfillment_method)

    assign(socket, show_delivery_inputs: fulfillment_method == :delivery)
  end

  defp ensure_valid_delivery_address(socket, params) do
    %{"fulfillment_option_id" => id, "delivery_address" => delivery_address} = params

    with %{fulfillment_method: :delivery} <- Enum.find(socket.assigns.fulfillment_options, &(&1.id == id)),
         {:ok, delivery_address} <- ensure_non_empty_value(delivery_address) do
      {:ok, delivery_address}
    else
      _ -> {:error, {:delivery_address_required, gettext("Delivery address is required")}}
    end
  end

  # Return socket if the field has not yet been interacted with
  defp validate_delivery_address(socket, %{"_unused_delivery_address" => ""}), do: socket

  defp validate_delivery_address(socket, params) do
    case ensure_valid_delivery_address(socket, params) do
      {:ok, _} ->
        add_field_error(socket, :delivery_address, nil)

      {:error, {_error, error_msg}} ->
        add_field_error(socket, :delivery_address, error_msg)
    end
  end

  defp add_field_error(socket, field, error_msg) when is_atom(field) do
    errors = Map.put(socket.assigns.errors, field, error_msg)
    assign(socket, errors: errors)
  end

  # ╔════════════════════╗
  # ║ Payment Processing ║
  # ╚════════════════════╝

  defp setup_payment_intent(socket, %{payment_intent_id: nil} = order) do
    amount = zero_decimal(order.total)

    {:ok, payment_intent} =
      Stripe.PaymentIntent.create(%{
        amount: amount,
        currency: "EUR",
        automatic_payment_methods: %{enabled: true, allow_redirects: :never}
      })

    order = Order.add_payment_intent_id!(order, payment_intent.id, load: order_load_statement())

    socket
    |> assign(order: order)
    |> assign(stripe_client_secret: payment_intent.client_secret)
  end

  defp setup_payment_intent(socket, %{payment_intent_id: payment_intent_id} = _order) do
    {:ok, payment_intent} = Stripe.PaymentIntent.retrieve(payment_intent_id)

    socket
    |> assign(stripe_client_secret: payment_intent.client_secret)
  end

  # TODO: perform the update asynchronously?
  defp update_payment_intent(socket, %{payment_intent_id: payment_intent_id, total: total}) do
    amount = zero_decimal(total)

    case Stripe.PaymentIntent.update(payment_intent_id, %{amount: amount}) do
      {:ok, _} ->
        Logger.info("Updated Stripe Payment Intent #{payment_intent_id} to amount #{amount}")
        socket

      {:error, reason} ->
        Logger.error("Failed to update Stripe Payment Intent #{payment_intent_id}: #{inspect(reason)}")
        socket
    end
  end

  # ╔═══════════╗
  # ║ Utilities ║
  # ╚═══════════╝

  defp zero_decimal(n) do
    n
    |> Decimal.mult(100)
    |> Decimal.to_integer()
  end

  defp ensure_non_empty_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:empty_value, gettext("Empty value")}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp format_options_for_select(resources) when is_list(resources) do
    Enum.map(resources, &{&1.name, &1.id})
  end

  defp create_step_action_name(action, step) when is_atom(action) and is_integer(step) do
    String.to_atom("#{action}_step_#{step}")
  end
end
