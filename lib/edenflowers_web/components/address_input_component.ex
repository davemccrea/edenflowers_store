defmodule EdenflowersWeb.AddressInputComponent do
  @moduledoc """
  Delivery address input with asynchronous geocoding on blur.

  Owns the blur event, the async HERE API call, and the loading/confirmed
  visual feedback. The field itself is rendered inside the parent's `<.form>`,
  so submitting step 3 carries the delivery_address value along with the
  other step-3 fields.

  After every geocode attempt (success or failure) the component sends a
  single `{:address_result, %{order: order, typed_address: typed, error:
  error_or_nil}}` message to the parent LiveView, which is responsible for
  reconciling the form. `typed_address` is the value the user blurred away
  from — the parent replays it into form params so a failure error renders
  on the correct field regardless of whether phx-change landed first.
  """
  use EdenflowersWeb, :live_component

  require Logger
  import EdenflowersWeb.CoreComponents

  alias Edenflowers.Store.Order

  @impl true
  def mount(socket) do
    {:ok, assign(socket, loading: false, typed_address: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.input
        label={~t"Address *"}
        field={@form[:delivery_address]}
        type="text"
        phx-blur="geocode"
        phx-target={@myself}
        loading={@loading}
        confirmed={@order.address_confirmed? and not @loading}
      />
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
  def handle_event("geocode", %{"value" => address}, socket) do
    order = socket.assigns.order

    cond do
      String.trim(address) == "" ->
        {:noreply, socket}

      # Address unchanged and already confirmed — nothing to do.
      order.address_confirmed? and address == order.delivery_address ->
        {:noreply, socket}

      true ->
        actor = socket.assigns.actor

        # start_async with the same name cancels any in-flight geocode, so the
        # final blur wins when the user types fast.
        {:noreply,
         socket
         |> assign(loading: true, typed_address: address)
         |> start_async(:confirm_delivery_address, fn ->
           Order.confirm_delivery_address(order, address, actor: actor)
         end)}
    end
  end

  @impl true
  def handle_async(:confirm_delivery_address, {:ok, {:ok, order}}, socket) do
    send(self(), {:address_result, %{order: order, typed_address: socket.assigns.typed_address, error: nil}})
    {:noreply, assign(socket, loading: false, order: order)}
  end

  def handle_async(:confirm_delivery_address, {:ok, {:error, %Ash.Error.Invalid{} = error}}, socket) do
    {:noreply, fail(socket, error)}
  end

  # Cancelled by a newer start_async with the same name — ignore, the new
  # task will deliver the user-facing result.
  def handle_async(:confirm_delivery_address, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, socket}
  end

  # Catch-all for any unexpected shape (non-Ash-error returns, task exits).
  # ConfirmDeliveryAddress is contracted to return {:ok, order} or
  # {:error, %Ash.Error.Invalid{}}; anything else is a bug we want to log
  # without crashing the checkout.
  def handle_async(:confirm_delivery_address, result, socket) do
    Logger.error("confirm_delivery_address unexpected result: #{inspect(result)}")
    {:noreply, fail(socket, generic_error())}
  end

  defp fail(socket, error) do
    order = socket.assigns.order

    order =
      if order.address_confirmed? do
        Order.clear_delivery_fields!(order, actor: socket.assigns.actor)
      else
        order
      end

    send(self(), {:address_result, %{order: order, typed_address: socket.assigns.typed_address, error: error}})
    assign(socket, loading: false, order: order)
  end

  defp generic_error do
    [field: :delivery_address, message: ~t"There was a problem calculating delivery cost, please try again later"]
  end

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
