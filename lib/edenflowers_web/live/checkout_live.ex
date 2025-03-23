defmodule EdenflowersWeb.CheckoutLive do
  use EdenflowersWeb, :live_view

  require Logger

  alias Edenflowers.{HereAPI, Fulfillments}
  alias Edenflowers.Store.{FulfillmentOption, Order}

  def mount(_params, session, socket) do
    order =
      Order
      |> Ash.get!(session["order_id"])
      |> Ash.load!(:fulfillment_option)

    fulfillment_options = Ash.read!(FulfillmentOption)

    form =
      order
      |> AshPhoenix.Form.for_update(create_step_action_name(:save, order.step))
      |> to_form()

    if order.payment_intent_id do
      # Update the total
    else
      # Create payment intent with current order total
    end

    {:ok,
     socket
     |> assign(id: "checkout")
     |> assign(page_title: "Checkout")
     |> assign(fulfillment_options: fulfillment_options)
     |> assign(order: order)
     |> assign(form: form)
     |> assign(errors: %{delivery_address: nil})
     |> set_delivery_fields_visibility(order.fulfillment_option_id)}
  end

  def render(assigns) do
    ~H"""
    <div class="lg:mx-36 xl:mx-48">
      <div class="flex flex-col gap-12">
        <div class="text-neutral/60 flex flex-row gap-2">
          <.icon name="hero-lock-closed" class="h-4 w-4" />
          <span class="items-center text-xs uppercase">Secure Checkout</span>
        </div>

        <div class="flex flex-row gap-8">
          <div id={@id} class="w-[60%]" phx-hook="Scroll">
            <%= if @order.step == 1 do %>
              <section id={"#{@id}-section-1"} class="checkout__section">
                <.form_heading>{gettext("Delivery")}</.form_heading>

                <.form
                  :if={@order.step == 1}
                  id="checkout-form-1"
                  for={@form}
                  phx-change="validate_form_1"
                  phx-submit="save_form_1"
                  class="checkout__form"
                >
                  <.input
                    label={gettext("Delivery Method")}
                    field={@form[:fulfillment_option_id]}
                    options={format_options_for_select(@fulfillment_options)}
                    type="select"
                  />

                  <.input
                    hint="You will receive a text message when your order is ready for collection."
                    label="Phone Number"
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

                  <div class="flex flex-col">
                    <.label>Delivery Date</.label>
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
                  </div>

                  <.form_button>Next <.icon name="hero-arrow-right" class="h-4 w-4" /></.form_button>
                </.form>
              </section>

              <div class="checkout__heading-container">
                <.form_heading active={false}>Customise</.form_heading>
                <.form_heading active={false}>Payment</.form_heading>
              </div>
            <% end %>

            <%= if @order.step == 2 do %>
              <div class="checkout__heading-container">
                <.form_heading step={1} active={false}>Delivery</.form_heading>
              </div>

              <section id={"#{@id}-section-2"} class="checkout__section">
                <.form_heading>Customise</.form_heading>

                <.form
                  id="checkout-form-2"
                  for={@form}
                  phx-change="validate_form_2"
                  phx-submit="save_form_2"
                  class="checkout__form"
                >
                  <div id="gift-message-container" phx-hook="CharacterCount">
                    <div class="relative flex flex-col">
                      <textarea
                        id={@form[:gift_message].id}
                        name={@form[:gift_message].name}
                        class="textarea w-full resize-none"
                        maxlength={200}
                        rows={5}
                      >{@form[:gift_message].value}</textarea>
                      <div class="absolute right-2 bottom-1">
                        <span class="text-xs" id="gift-message-char-count" phx-update="ignore">0/200</span>
                      </div>
                    </div>

                    <.error :for={msg <- Enum.map(@form[:gift_message].errors, &translate_error(&1))}>
                      {gettext("Gift Message")} {msg}
                    </.error>
                  </div>

                  <.form_button>Next <.icon name="hero-arrow-right" class="h-4 w-4" /></.form_button>
                </.form>
              </section>

              <div class="checkout__heading-container">
                <.form_heading active={false}>Payment</.form_heading>
              </div>
            <% end %>

            <%= if @order.step == 3 do %>
              <div class="checkout__heading-container">
                <.form_heading step={1} active={false}>Delivery</.form_heading>
                <.form_heading step={2} active={false}>Customise</.form_heading>
              </div>

              <section id={"#{@id}-section-3"} class="checkout__section">
                <.form_heading>Payment</.form_heading>

                <.form
                  id="checkout-form-3"
                  for={@form}
                  phx-change="validate_form_3"
                  phx-submit="save_form_3"
                  class="checkout__form"
                >
                  <div id="stripe-elements" phx-hook="StripeElements"></div>
                </.form>
              </section>
            <% end %>
          </div>

          <div class="md:border-neutral/5 md:border-r"></div>

          <div class="w-[35%] sticky top-6 h-fit overflow-y-auto">
            <div class="flex flex-col gap-6">
              <%!-- Heading --%>
              <h2 class="font-bold">Your Cart</h2>

              <%!-- Cart products --%>
              <div class="flex flex-col gap-2">
                <div class="flex flex-row gap-4 text-sm">
                  <div class="flex flex-row gap-4">
                    <div class="h-14 w-14 rounded bg-blue-100"></div>
                    <div class="flex flex-col">
                      <span>Spring Bouquet (medium)</span>
                      <span>€45.00</span>
                    </div>
                  </div>
                </div>

                <div class="flex flex-row gap-4 text-sm">
                  <div class="flex flex-row gap-4">
                    <div class="h-14 w-14 rounded bg-yellow-100"></div>
                    <div class="flex flex-col">
                      <span>Autumn Bouquet (large)</span>
                      <span>€60.00</span>
                    </div>
                  </div>
                </div>
              </div>

              <div class="border-neutral/5 border-t"></div>

              <%!-- Line items --%>
              <div class="flex flex-col gap-2 text-sm">
                <div class="flex justify-between">
                  <span>Subtotal</span>
                  <span>€70.00</span>
                </div>

                <div class="flex justify-between">
                  <span>Delivery</span>
                  <span>€5.99</span>
                </div>

                <div class="flex justify-between">
                  <span>Discount</span>
                  <span class="text-green-600">-€10.00</span>
                </div>

                <div class="flex justify-between font-semibold">
                  <span>Total</span>
                  <span>€65.99</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Components

  slot :inner_block
  attr :step, :integer, default: nil
  attr :active, :boolean, default: true
  attr :rest, :global

  defp form_heading(assigns) do
    ~H"""
    <div class="flex flex-row justify-between">
      <h1 class={"#{if not @active, do: "text-neutral/40", else: "text-neutral"} font-serif text-2xl font-medium"} {@rest}>
        {render_slot(@inner_block)}
      </h1>
      <%= if @step do %>
        <button class="btn btn-ghost" phx-click={"edit_step_#{@step}"}>Edit</button>
      <% end %>
    </div>
    """
  end

  slot :inner_block
  attr :rest, :global

  defp form_button(assigns) do
    ~H"""
    <button type="submit" class="btn btn-primary btn-lg mt-2 flex flex-row gap-2">
      <span class="phx-submit-loading:loading phx-submit-loading:loading-spinner"></span>
      <span>{render_slot(@inner_block)}</span>
    </button>
    """
  end

  # Event handlers

  def handle_event("validate_form_1", %{"form" => params}, socket) do
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

  def handle_event("save_form_1", %{"form" => %{"fulfillment_option_id" => id} = params}, socket) do
    fulfillment_option = Enum.find(socket.assigns.fulfillment_options, &(&1.id == id))

    if fulfillment_option.fulfillment_method == :delivery do
      {:noreply, calculate_delivery_details(socket, params, fulfillment_option)}
    else
      {:noreply, process_pickup(socket, params, fulfillment_option)}
    end
  end

  def handle_event("save_form_" <> _step, %{"form" => params}, socket) do
    {:noreply, update_order_and_form(socket, params)}
  end

  def handle_event("edit_step_" <> step, _params, %{assigns: %{order: order}} = socket) do
    step = String.to_integer(step)

    order =
      order
      |> Ash.Changeset.for_update(create_step_action_name(:edit, step))
      |> Ash.update!()

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

  # Helper functions

  defp process_pickup(socket, params, fulfillment_option) do
    {:ok, fulfillment_amount} = Fulfillments.calculate_price(fulfillment_option)

    # Note: use string keys below because form uses string keys
    params =
      Map.merge(params, %{
        "fulfillment_amount" => fulfillment_amount,
        "delivery_address" => nil,
        "calculated_address" => nil,
        "here_id" => nil,
        "distance" => nil,
        "position" => nil
      })

    update_order_and_form(socket, params)
  end

  defp calculate_delivery_details(socket, params, fulfillment_option) do
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

      update_order_and_form(socket, params)
    else
      {:error, {_error, error_msg}} ->
        add_field_error(socket, :delivery_address, error_msg)

      error ->
        Logger.error("Unhandled error in calculate_delivery_details: #{inspect(error)}")
        update_order_and_form(socket, params)
    end
  end

  defp update_order_and_form(socket, params) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
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

  defp add_field_error(socket, field, error_msg) when is_atom(field) do
    errors = Map.put(socket.assigns.errors, field, error_msg)
    assign(socket, errors: errors)
  end

  defp validate_delivery_address(socket, %{"_unused_delivery_address" => ""}), do: socket

  defp validate_delivery_address(socket, params) do
    case ensure_valid_delivery_address(socket, params) do
      {:ok, _} ->
        socket
        |> add_field_error(:delivery_address, nil)

      {:error, {_error, error_msg}} ->
        socket
        |> add_field_error(:delivery_address, error_msg)
    end
  end

  defp ensure_valid_delivery_address(socket, params) do
    %{assigns: %{fulfillment_options: fulfillment_options}} = socket
    %{"fulfillment_option_id" => id, "delivery_address" => delivery_address} = params

    with %{fulfillment_method: :delivery} <- Enum.find(fulfillment_options, &(&1.id == id)),
         {:ok, delivery_address} <- ensure_non_empty_value(delivery_address) do
      {:ok, delivery_address}
    else
      _ -> {:error, {:delivery_address_required, gettext("Delivery address is required")}}
    end
  end

  defp ensure_non_empty_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:empty_value, gettext("Empty value")}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp set_delivery_fields_visibility(socket, fulfillment_id) do
    fulfillment_method =
      socket.assigns.fulfillment_options
      |> Enum.find(&(&1.id == fulfillment_id))
      |> Map.get(:fulfillment_method)

    assign(socket, show_delivery_inputs: fulfillment_method == :delivery)
  end

  defp format_options_for_select(resources) when is_list(resources) do
    Enum.map(resources, &{&1.name, &1.id})
  end

  defp create_step_action_name(action, step) when is_atom(action) and is_integer(step) do
    String.to_atom("#{action}_step_#{step}")
  end
end
