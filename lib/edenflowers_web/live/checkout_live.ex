defmodule EdenflowersWeb.CheckoutLive do
  use EdenflowersWeb, :live_view

  require Logger
  require Ash.Query

  alias Edenflowers.{HereAPI, Fulfillments}
  alias Edenflowers.Store.{FulfillmentOption, Order}

  def mount(_params, %{"order_id" => id}, socket) do
    with order = %Order{} <- fetch_order(id),
         {:ok, _line_items} <- validate_cart(order),
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
       |> setup_stripe(order)
       |> set_delivery_fields_visibility(order.fulfillment_option_id)}
    else
      {:error, :empty_cart} ->
        {:ok, push_navigate(socket, to: ~p"/")}

      _ ->
        {:ok, redirect(socket, to: ~p"/")}
    end
  end

  # ╔═══════════════╗
  # ║ Mount Helpers ║
  # ╚═══════════════╝

  defp fetch_order(id) do
    Order
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.load(order_load_statement())
    |> Ash.read_one!()
  end

  defp validate_cart(%{line_items: []}), do: {:error, :empty_cart}
  defp validate_cart(%{line_items: line_items}), do: {:ok, line_items}

  # ╔════════╗
  # ║ Markup ║
  # ╚════════╝

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mt-[calc(var(--header-height)+var(--spacing)*8)] mx-4 mb-24 lg:mx-24 xl:mx-48 2xl:mx-96">
        <div class="flex flex-col gap-12">
          <div class="text-neutral/60 flex flex-row gap-2">
            <.icon name="hero-lock-closed" class="h-4 w-4" />
            <span class="items-center text-xs uppercase">{gettext("Secure Checkout")}</span>
          </div>

          <div class="flex flex-col gap-8 md:flex-row">
            <div id={@id} class="md:w-[60%]">
              <%= if @order.step == 1 do %>
                <section id={"#{@id}-section-1"} class="checkout__section">
                  <.form_heading>{gettext("Personalise")}</.form_heading>

                  <.form
                    :if={@order.step == 1}
                    id="checkout-form-1"
                    for={@form}
                    phx-change="validate_form_1"
                    phx-submit="save_form_1"
                    class="checkout__form"
                  >
                    <div id="gift-message-container" phx-hook="CharacterCount">
                      <fieldset>
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
                      </fieldset>

                      <.error :for={msg <- Enum.map(@form[:gift_message].errors, &translate_error(&1))}>
                        {gettext("Gift Message")} {msg}
                      </.error>
                    </div>

                    <.form_button>Next</.form_button>
                  </.form>
                </section>

                <div class="checkout__heading-container">
                  <.form_heading active={false}>{gettext("Personalise")}</.form_heading>
                  <.form_heading active={false}>{gettext("Payment")}</.form_heading>
                </div>
              <% end %>

              <%= if @order.step == 2 do %>
                <div class="checkout__heading-container">
                  <.form_heading step={1} active={false}>{gettext("Personalise")}</.form_heading>
                </div>

                <section id={"#{@id}-section-2"} class="checkout__section">
                  <.form_heading>{gettext("Delivery")}</.form_heading>

                  <.form
                    id="checkout-form-2"
                    for={@form}
                    phx-change="validate_form_2"
                    phx-submit="save_form_2"
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
                      hint="You will receive a text message when your order is ready for collection."
                      label={gettext("Phone Number")}
                      placeholder="045 1505141"
                      field={@form[:recipient_phone_number]}
                      type="text"
                    />

                    <div id="delivery-fields" class={"#{not @show_delivery_inputs && "hidden"} flex flex-col space-y-4"}>
                      <div>
                        <.input
                          hint="The delivery fee is calcuted based on distance from Minimosen."
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

                <div class="checkout__heading-container">
                  <.form_heading active={false}>{gettext("Payment")}</.form_heading>
                </div>
              <% end %>

              <%= if @order.step == 3 do %>
                <div class="checkout__heading-container">
                  <.form_heading step={1} active={false}>{gettext("Personalise")}</.form_heading>
                  <.form_heading step={2} active={false}>{gettext("Delivery")}</.form_heading>
                </div>

                <section id={"#{@id}-section-3"} class="checkout__section">
                  <.form_heading>{gettext("Payment")}</.form_heading>

                  <.form
                    id="checkout-form-3"
                    for={@form}
                    phx-change="validate_form_3"
                    phx-submit="save_form_3"
                    class="checkout__form"
                  >
                    <div
                      class="max-w-xl"
                      id="payment-element"
                      data-client-secret={@stripe_client_secret}
                      phx-hook="PaymentElement"
                    >
                    </div>

                    <.form_button id="payment-button" disabled={true}>
                      Pay {Edenflowers.Utils.format_money(@order.total)}
                    </.form_button>
                  </.form>
                </section>
              <% end %>
            </div>

            <div class="md:border-neutral/10 md:border-r"></div>

            <div class="md:w-[35%] md:sticky md:top-6 md:h-fit md:overflow-y-auto">
              <div class="flex flex-col gap-4 p-1">
                <h2 class="font-serif text-xl">
                  {gettext("Cart")} ({if @order.total_items_in_cart, do: @order.total_items_in_cart, else: 0})
                </h2>

                <div :for={line_item <- @order.line_items} class="flex flex-col gap-2">
                  <div class="flex flex-row justify-between gap-4 text-sm">
                    <div class="flex flex-row gap-4">
                      <img
                        class="h-18 w-18 rounded"
                        src={line_item.product_variant.image}
                        alt={"Image of #{line_item.product_variant.product.name}"}
                      />
                      <div class="flex flex-col">
                        <span>{line_item.product_variant.product.name}</span>
                      </div>
                    </div>
                    <span>{Edenflowers.Utils.format_money(line_item.product_variant.price)}</span>
                  </div>
                </div>

                <div class="join">
                  <label class="input join-item w-full">
                    <input type="email" placeholder="Enter promo code" required />
                  </label>
                  <button class="btn btn-primary join-item">{gettext("Apply")}</button>
                </div>

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
                    <span>{gettext("Discount")}</span>
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
              </div>
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
  attr :step, :integer, default: nil
  attr :active, :boolean, default: true
  attr :rest, :global

  defp form_heading(assigns) do
    ~H"""
    <div class="flex flex-row items-center justify-between">
      <h1 class={"#{if not @active, do: "text-neutral/40", else: "text-neutral"} font-serif text-3xl"} {@rest}>
        {render_slot(@inner_block)}
      </h1>
      <%= if @step do %>
        <button class="btn btn-ghost text-neutral/40" phx-click={"edit_step_#{@step}"}>Edit</button>
      <% end %>
    </div>
    """
  end

  slot :inner_block
  attr :disabled, :boolean
  attr :rest, :global

  defp form_button(assigns) do
    ~H"""
    <button {@rest} type="submit" class="btn btn-primary btn-lg mt-2 flex flex-row gap-2">
      <span class="phx-submit-loading:loading phx-submit-loading:loading-spinner"></span>
      <span>{render_slot(@inner_block)}</span>
    </button>
    """
  end

  # ╔═══════════════╗
  # ║ Event Helpers ║
  # ╚═══════════════╝

  def handle_event("validate_form_2", %{"form" => params}, socket) do
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

  def handle_event("save_form_2", %{"form" => %{"fulfillment_option_id" => id} = params}, socket) do
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
     |> push_event("scroll", %{anchor: "#{socket.assigns.id}-section-#{order.step}"})
     |> assign(order: order)
     |> assign(form: form)}
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
        |> push_event("scroll", %{anchor: "#{socket.assigns.id}-section-#{order.step}"})
        |> assign(order: order)
        |> assign(form: form)

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

      error ->
        Logger.error("Unhandled error in handle_fulfillment_method: #{inspect(error)}")
        submit(socket, params)
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

  defp setup_stripe(socket, %{payment_intent_id: nil} = order) do
    # amount =
    #   order.total
    #   |> Decimal.mult(100)
    #   |> Decimal.to_integer()

    # Create payment intent with current order total
    {:ok, payment_intent} =
      Stripe.PaymentIntent.create(%{
        # TODO
        amount: 100,
        currency: "EUR",
        automatic_payment_methods: %{enabled: true}
      })

    order =
      order
      |> Ash.Changeset.for_update(:add_payment_intent_id, %{payment_intent_id: payment_intent.id()})
      |> Ash.update!(load: order_load_statement())

    assign(socket, order: order)
  end

  defp setup_stripe(socket, %{payment_intent_id: payment_intent_id} = _order) when is_binary(payment_intent_id) do
    {:ok, payment_intent} = Stripe.PaymentIntent.retrieve(payment_intent_id)
    assign(socket, stripe_client_secret: payment_intent.client_secret)
  end

  # ╔═══════════╗
  # ║ Utilities ║
  # ╚═══════════╝

  defp order_load_statement do
    [
      :total_items_in_cart,
      :promotion_applied?,
      :discount_amount,
      :total,
      :fulfillment_option,
      :tax_amount,
      {:line_items, [product_variant: :product]}
    ]
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
