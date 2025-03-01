defmodule EdenflowersWeb.CheckoutLive do
  alias Edenflowers.Fulfillments
  use EdenflowersWeb, :live_view

  require Logger

  alias Edenflowers.HereAPI
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

    {:ok,
     socket
     |> assign(page_title: "Checkout")
     |> assign(fulfillment_options: fulfillment_options)
     |> assign(order: order)
     |> assign(form: form)
     |> assign(errors: %{delivery_address: nil})
     |> set_delivery_fields_visibility(order.fulfillment_option_id)}
  end

  def render(assigns) do
    ~H"""
    <div class="m-auto max-w-xl">
      <%= if @order.step == 1 do %>
        <section class="checkout__section">
          <.form_heading>{gettext("Delivery")}</.form_heading>

          <.form
            :if={@order.step == 1}
            id="checkout-step-1"
            phx-hook="Spinner"
            for={@form}
            phx-change="validate_step_1"
            phx-submit="save_step_1"
            class="checkout__form"
          >
            <.input
              class="wa"
              label={gettext("Delivery Method")}
              field={@form[:fulfillment_option_id]}
              options={format_options_for_select(@fulfillment_options)}
              type="select"
            />

            <.input
              hint="You will receive a text message when your order is ready for collection."
              label="Phone Number"
              field={@form[:recipient_phone_number]}
              type="text"
            />

            <div id="delivery-fields" class={"#{not @show_delivery_inputs && "hidden"} flex flex-col space-y-4"}>
              <div>
                <.input
                  hint="The delivery fee is calcuted based on distance."
                  placeholder=""
                  label="Address *"
                  field={@form[:delivery_address]}
                  type="text"
                />
                <.error :if={@errors[:delivery_address]}>{@errors[:delivery_address]}</.error>
              </div>

              <.input label="Delivery Instructions" field={@form[:delivery_instructions]} type="text" />
            </div>

            <wa-button class="submit-button" type="submit">Next</wa-button>
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

        <section class="checkout__section">
          <.form_heading>Customise</.form_heading>

          <.form
            id="checkout-step-2"
            phx-hook="Spinner"
            for={@form}
            phx-change="validate_step_2"
            phx-submit="save_step_2"
            class="checkout__form"
          >
            <div class="space-y-2">
              <.label for="card-picker">Choose a Card</.label>
              <div id="card-picker" class="relative w-full">
                <div class="flex snap-x snap-mandatory flex-row gap-4 overflow-x-auto pb-4">
                  <div
                    :for={
                      color <- [
                        "bg-red-100",
                        "bg-orange-100",
                        "bg-amber-100",
                        "bg-yellow-100",
                        "bg-lime-100",
                        "bg-green-100",
                        "bg-emerald-100",
                        "bg-teal-100",
                        "bg-cyan-100",
                        "bg-sky-100",
                        "bg-blue-100",
                        "bg-indigo-100",
                        "bg-violet-100",
                        "bg-purple-100",
                        "bg-pink-100"
                      ]
                    }
                    class={"#{color} aspect-square h-auto w-64 flex-none snap-center rounded-lg"}
                  >
                  </div>
                </div>
              </div>
            </div>

            <div id="gift-message-container" phx-hook="CharacterCount">
              <div class="relative">
                <.label for={@form[:gift_message].id}>
                  Gift Message <textarea
                    id={@form[:gift_message].id}
                    name={@form[:gift_message].name}
                    maxlength={200}
                    rows={5}
                  >{@form[:gift_message].value}</textarea>
                </.label>

                <div class="absolute right-2 bottom-1">
                  <span class="text-xs" id="gift-message-char-count" phx-update="ignore">0/200</span>
                </div>
              </div>

              <.error :for={msg <- Enum.map(@form[:gift_message].errors, &translate_error(&1))}>
                {gettext("Gift Message")} {msg}
              </.error>
            </div>

            <wa-button class="submit-button" type="submit">Next</wa-button>
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

        <section class="checkout__section">
          <.form_heading>Payment</.form_heading>

          <.form
            id="checkout-step-3"
            phx-hook="Spinner"
            for={@form}
            phx-change="validate_step_3"
            phx-submit="save_step_3"
            class="checkout__form"
          >
          </.form>
        </section>
      <% end %>
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
      <h1 class={"#{not @active && "text-neutral-400"} font-serif text-3xl"} {@rest}>
        {render_slot(@inner_block)}
      </h1>
      <%= if @step do %>
        <wa-button phx-click={"edit_step_#{@step}"} appearance="plain" variant="neutral">Edit</wa-button>
      <% end %>
    </div>
    """
  end

  # Event handlers

  def handle_event("validate_step_1", %{"form" => params}, socket) do
    fulfillment_option_id = Map.get(params, "fulfillment_option_id")
    form = AshPhoenix.Form.validate(socket.assigns.form, params)

    {:noreply,
     socket
     |> validate_delivery_address(params)
     |> set_delivery_fields_visibility(fulfillment_option_id)
     |> assign(form: form)}
  end

  def handle_event("validate_step_" <> _step, %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save_step_1", %{"form" => %{"fulfillment_option_id" => id} = params}, socket) do
    fulfillment_option = Enum.find(socket.assigns.fulfillment_options, &(&1.id == id))

    if fulfillment_option.fulfillment_method == :delivery do
      {:noreply, calculate_delivery_details(socket, params, fulfillment_option)}
    else
      {:noreply, process_pickup(socket, params, fulfillment_option)}
    end
  end

  def handle_event("save_step_" <> _step, %{"form" => params}, socket) do
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
      {:error, error} ->
        Logger.error("#{inspect(error)}")
        add_field_error(socket, :delivery_address, error)

      error ->
        Logger.error("#{inspect(error)}")
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
        |> assign(order: order)
        |> assign(form: form)

      {:error, form} ->
        assign(socket, form: form)
    end
  end

  defp add_field_error(socket, field, error) when is_atom(field) do
    error_message =
      case error do
        :geocode -> gettext("Address not found")
        :delivery_address_required -> gettext("Address is required")
        _ -> nil
      end

    errors = Map.put(socket.assigns.errors, field, error_message)
    assign(socket, errors: errors)
  end

  defp validate_delivery_address(socket, %{"_unused_delivery_address" => ""}), do: socket

  defp validate_delivery_address(socket, params) do
    case ensure_valid_delivery_address(socket, params) do
      {:ok, _} ->
        socket
        |> add_field_error(:delivery_address, nil)

      {:error, error} ->
        socket
        |> add_field_error(:delivery_address, error)
    end
  end

  defp ensure_valid_delivery_address(socket, params) do
    %{assigns: %{fulfillment_options: options}} = socket
    %{"fulfillment_option_id" => id, "delivery_address" => delivery_address} = params

    with %{fulfillment_method: :delivery} <- Enum.find(options, &(&1.id == id)),
         {:ok, delivery_address} <- ensure_non_empty_value(delivery_address) do
      {:ok, delivery_address}
    else
      _ -> {:error, :delivery_address_required}
    end
  end

  defp ensure_non_empty_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :empty_value}
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
    "#{action}_step_#{step}" |> String.to_atom()
  end
end
