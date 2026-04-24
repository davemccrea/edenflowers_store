defmodule EdenflowersWeb.AddressInputComponent do
  @moduledoc """
  Delivery address input with asynchronous geocoding on blur.

  Self-contained: renders its own `<input>` inside a component-scoped
  `<.form>`, separate from the parent's step-3 form. The persisted
  `order.delivery_address` / `order.geocoded_address` are the source of
  truth — form params never carry an address. On every mutation the
  component sends `{:order_updated, order}` so the parent can refresh
  its assigns.

  The server-side rule "delivery orders must have a geocoded address"
  lives on the `save_step_3` action (see `ValidateGeocodedAddress`).
  When submit fails for that reason, the parent mirrors the error into
  the component with `send_update(__MODULE__, id: "address-input",
  required_error: true)` so the message renders where the user is
  looking.
  """
  use EdenflowersWeb, :live_component
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger
  import EdenflowersWeb.CoreComponents

  alias Edenflowers.Store.Order

  @impl true
  def mount(socket) do
    {:ok, assign(socket, loading: false, typed: nil, error: nil)}
  end

  @impl true
  def update(%{required_error: true}, socket) do
    {:ok, assign(socket, error: {:required, ~t"Delivery address required"})}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:typed, fn -> assigns.order.delivery_address end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={%{}}
        as={:address}
        phx-change="typing"
        phx-submit="noop"
        phx-target={@myself}
      >
        <.input
          id="address-input-field"
          name="delivery_address"
          value={@typed}
          label={~t"Address *"}
          type="text"
          errors={errors(@error)}
          phx-blur="geocode"
          phx-target={@myself}
          loading={@loading}
          confirmed={@order.address_confirmed? and not @loading}
        />
      </.form>
      <p
        :if={@order.address_confirmed? and not @loading}
        data-testid="address-distance"
        class="mt-1.5 text-sm"
      >
        {format_distance(@order.distance)} • {format_delivery_amount(@order)}
      </p>
    </div>
    """
  end

  @impl true
  def handle_event("typing", %{"delivery_address" => value}, socket) do
    order = socket.assigns.order
    was_confirmed? = order.address_confirmed?
    became_blank? = String.trim(value) == ""

    socket =
      cond do
        # User emptied a previously confirmed address — clear server-side
        # geocode and surface the required error.
        was_confirmed? and became_blank? ->
          order = Order.clear_delivery_fields!(order, actor: socket.assigns.actor)
          send(self(), {:order_updated, order})
          assign(socket, order: order, typed: value, error: {:required, ~t"Delivery address required"})

        # User is editing a confirmed address into something different —
        # drop the stale geocode; the required error only applies to the
        # empty-confirmed case.
        was_confirmed? and value != order.delivery_address ->
          order = Order.clear_delivery_fields!(order, actor: socket.assigns.actor)
          send(self(), {:order_updated, order})
          assign(socket, order: order, typed: value, error: nil)

        true ->
          assign(socket, typed: value, error: nil)
      end

    {:noreply, socket}
  end

  def handle_event("geocode", %{"value" => address}, socket) do
    order = socket.assigns.order

    cond do
      String.trim(address) == "" ->
        {:noreply, socket}

      order.address_confirmed? and address == order.delivery_address ->
        {:noreply, socket}

      true ->
        actor = socket.assigns.actor

        # start_async with the same name cancels any in-flight geocode, so the
        # final blur wins when the user types fast.
        {:noreply,
         socket
         |> assign(loading: true, typed: address, error: nil)
         |> start_async(:confirm_delivery_address, fn ->
           Order.confirm_delivery_address(order, address, actor: actor)
         end)}
    end
  end

  def handle_event("noop", _, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:confirm_delivery_address, {:ok, {:ok, order}}, socket) do
    send(self(), {:order_updated, order})

    {:noreply,
     assign(socket,
       loading: false,
       order: order,
       typed: order.delivery_address,
       error: nil
     )}
  end

  def handle_async(:confirm_delivery_address, {:ok, {:error, %Ash.Error.Invalid{} = error}}, socket) do
    {:noreply, fail(socket, extract_message(error))}
  end

  def handle_async(:confirm_delivery_address, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, socket}
  end

  def handle_async(:confirm_delivery_address, result, socket) do
    Logger.error("confirm_delivery_address unexpected result: #{inspect(result)}")
    {:noreply, fail(socket, ~t"There was a problem calculating delivery cost, please try again later")}
  end

  defp fail(socket, message) do
    order = socket.assigns.order

    order =
      if order.address_confirmed? do
        cleared = Order.clear_delivery_fields!(order, actor: socket.assigns.actor)
        send(self(), {:order_updated, cleared})
        cleared
      else
        order
      end

    assign(socket, loading: false, order: order, error: {:api, message})
  end

  defp extract_message(%Ash.Error.Invalid{errors: errors}) do
    case Enum.find(errors, &match?(%{field: :delivery_address}, &1)) do
      %{message: message} -> message
      _ -> ~t"There was a problem calculating delivery cost, please try again later"
    end
  end

  defp errors({_kind, message}), do: [message]
  defp errors(nil), do: []

  defp format_distance(nil), do: ""

  defp format_distance(meters) when is_integer(meters) do
    km = meters / 1000
    if km < 1, do: "#{meters} m", else: "#{:erlang.float_to_binary(km, decimals: 1)} km"
  end

  defp format_delivery_amount(%{fulfillment_amount: nil}), do: ""

  defp format_delivery_amount(%{fulfillment_amount: amount}) do
    if Decimal.eq?(amount, 0), do: ~t"Free delivery! 🥳", else: Edenflowers.Utils.format_money(amount)
  end
end
