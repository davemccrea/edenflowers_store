defmodule EdenflowersWeb.CheckoutLive do
  use EdenflowersWeb, :live_view

  require Logger
  require Ash.Query

  alias Edenflowers.Store.{Order, FulfillmentOption, Promotion}
  alias Edenflowers.{Fulfillments, StripeAPI}

  def mount(_params, _session, %{assigns: %{order: order}} = socket) do
    with {:ok, _line_items} <- cart_has_items?(order),
         {:ok, fulfillment_options} <- Ash.read(FulfillmentOption) do
      form =
        order
        |> AshPhoenix.Form.for_update(action_name(:save, order.step))
        |> to_form()

      {:ok,
       socket
       |> assign(:id, "checkout")
       |> assign(:page_title, gettext("Checkout"))
       |> assign(fulfillment_options: fulfillment_options)
       |> assign(order: order)
       |> assign(form: form)
       |> assign(promo_form: %{})
       |> assign(errors: %{})
       |> setup_stripe(order)}
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

  # ╔════════╗
  # ║ Markup ║
  # ╚════════╝

  def render(assigns) do
    ~H"""
    <Layouts.app order={@order} flash={@flash}>
      <div class="mt-[calc(var(--header-height)+var(--spacing)*8)] mx-4 mb-24 lg:mx-24 xl:mx-48 2xl:mx-64">
        <div class="flex flex-col gap-12">
          <div class="text-neutral/60 flex flex-row gap-2">
            <.icon name="hero-lock-closed" class="h-4 w-4" />
            <span class="items-center text-xs uppercase">{gettext("Secure Checkout")}</span>
          </div>

          <div class="flex flex-col gap-8 md:flex-row">
            <div id={@id} class="md:w-[60%]">
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
                    <.input label={gettext("Name")} field={@form[:customer_name]} type="text" />
                    <.input label={gettext("Email")} field={@form[:customer_email]} type="text" />

                    <.form_button>Next</.form_button>
                  </.form>
                </section>

                <section :if={@order.step == 2} id={"#{@id}-section-2"} class="checkout__section">
                  <.form_heading>{gettext("Gift Options")}</.form_heading>

                  <.form
                    :if={@order.step == 2}
                    id={"#{@id}-form-2"}
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
                        {msg}
                      </.error>
                    </fieldset>

                    <.form_button>Next</.form_button>
                  </.form>
                </section>

                <section :if={@order.step == 3} id={"#{@id}-section-3"} class="checkout__section">
                  <.form_heading>{gettext("Delivery Information")}</.form_heading>

                  <.form id={"#{@id}-fulfillment-option"} for={%{}} phx-change="update_fulfillment_option">
                    <.input
                      :let={option}
                      type="radio-card"
                      field={@form[:fulfillment_option_id]}
                      options={Enum.map(@fulfillment_options, fn %{id: id, name: name} -> %{name: name, value: id} end)}
                      label={gettext("Delivery Method")}
                    >
                      {option.name}
                    </.input>
                  </.form>

                  <%= if not is_nil(@order.fulfillment_option) do %>
                    <.form
                      id={"#{@id}-form-3"}
                      for={@form}
                      phx-change="validate_form_3"
                      phx-submit="save_form_3"
                      class="checkout__form"
                    >
                      <.input
                        label={gettext("Phone Number")}
                        placeholder="045 1505141"
                        field={@form[:recipient_phone_number]}
                        type="text"
                      />

                      <%= if @order.fulfillment_option.fulfillment_method == :delivery do %>
                        <.input
                          placeholder="Stadsgatan 3, 65300 Vasa"
                          label="Address *"
                          field={@form[:delivery_address]}
                          type="text"
                        />

                        <.input label="Delivery Instructions" field={@form[:delivery_instructions]} type="text" />
                      <% end %>

                      <fieldset>
                        <label class="mb-1">{gettext("Delivery Date")}</label>
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
                        </.live_component>
                        <.input field={@form[:fulfillment_date]} hidden />
                      </fieldset>

                      <.form_button>Next</.form_button>
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
                    data-return-url={"http://localhost:4000/checkout/complete/#{@order.id}"}
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

            <div class="md:border-neutral/10 md:border-r"></div>

            <div class="md:w-[35%] md:sticky md:top-6 md:h-fit md:overflow-y-auto">
              <section class="flex flex-col gap-4 p-1">
                <h2 class="font-serif text-xl">
                  {gettext("Cart")} ({if @order.total_items_in_cart, do: @order.total_items_in_cart, else: 0})
                </h2>

                <.live_component id="checkout-line-items" module={EdenflowersWeb.LineItemsComponent} order={@order} />

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

  # ╔════════════════╗
  # ║ Event Handlers ║
  # ╚════════════════╝

  def handle_event("validate_form_" <> _step, %{"form" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save_form_4", _, socket) do
    StripeAPI.update_payment_intent(socket.assigns.order)
    {:noreply, push_event(socket, "stripe:process_payment", %{})}
  end

  def handle_event("save_form_" <> _step, %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, order} ->
        form =
          order
          |> AshPhoenix.Form.for_update(action_name(:save, order.step))
          |> to_form()

        {:noreply,
         socket
         |> assign(order: order)
         |> assign(form: form)}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("edit_step_" <> step, _params, %{assigns: %{order: order}} = socket) do
    step = String.to_integer(step)

    order =
      order
      |> Ash.Changeset.for_update(action_name(:edit, step))
      |> Ash.update!()

    form =
      order
      |> AshPhoenix.Form.for_update(action_name(:save, order.step))
      |> to_form()

    {:noreply,
     socket
     |> assign(order: order)
     |> assign(form: form)}
  end

  def handle_event("update_fulfillment_option", %{"form" => %{"fulfillment_option_id" => id}}, socket) do
    order = Order.update_fulfillment_option!(socket.assigns.order, id)

    form =
      order
      |> AshPhoenix.Form.for_update(action_name(:save, order.step))
      |> to_form()

    {:noreply, assign(socket, order: order, form: form)}
  end

  def handle_event("apply_promo", %{"code" => code}, socket) do
    case Promotion.get_by_code(code) do
      {:ok, promotion} ->
        errors = Map.put(socket.assigns.errors, :promo_code, nil)
        order = Order.add_promotion!(socket.assigns.order, promotion.id)

        {:noreply,
         socket
         |> assign(order: order)
         |> assign(errors: errors)
         |> assign(promo_form: %{})}

      _ ->
        errors = Map.put(socket.assigns.errors, :promo_code, gettext("Not found"))

        {:noreply,
         socket
         |> assign(errors: errors)
         |> assign(promo_form: %{})}
    end
  end

  def handle_event("clear_promo", _, socket) do
    order = Order.clear_promotion!(socket.assigns.order)
    {:noreply, assign(socket, order: order)}
  end

  def handle_event("stripe:error", %{"error" => error}, socket) do
    Logger.error("Stripe Hook Error: #{inspect(error)}")
    {:noreply, socket}
  end

  def handle_info({:date_selected, date}, socket) do
    form = AshPhoenix.Form.update_params(socket.assigns.form, &Map.put(&1, "fulfillment_date", date))
    {:noreply, assign(socket, form: form)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: "line_item:changed:" <> _order_id}, socket) do
    if Enum.empty?(socket.assigns.order.line_items),
      do: {:noreply, push_navigate(socket, to: ~p"/")},
      else: {:noreply, socket}
  end

  # ╔════════════╗
  # ║ Components ║
  # ╚════════════╝

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
        Edit
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

  # ╔═══════════╗
  # ║ Utilities ║
  # ╚═══════════╝

  defp cart_has_items?(%{line_items: []}), do: {:error, :empty_cart}
  defp cart_has_items?(%{line_items: line_items}), do: {:ok, line_items}

  defp setup_stripe(socket, %{payment_intent_id: nil} = order) do
    {:ok, payment_intent} = StripeAPI.create_payment_intent(order)
    order = Order.add_payment_intent_id!(order, payment_intent.id)

    socket
    |> assign(order: order)
    |> assign(client_secret: payment_intent.client_secret)
  end

  defp setup_stripe(socket, order) do
    {:ok, payment_intent} = StripeAPI.retrieve_payment_intent(order)
    assign(socket, client_secret: payment_intent.client_secret)
  end

  defp action_name(action, step) when is_atom(action) and is_integer(step) do
    String.to_atom("#{action}_step_#{step}")
  end
end
