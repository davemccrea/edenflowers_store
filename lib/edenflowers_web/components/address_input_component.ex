defmodule EdenflowersWeb.AddressInputComponent do
  @moduledoc """
  Delivery address input with asynchronous geocoding on blur.

  Owns the full lifecycle of the address confirmation flow: the blur event,
  the async HERE API call, the 5 possible async outcomes, and field-error
  surfacing. The parent LiveView passes in the order + parent form and
  receives `{:address_changed, order}` messages back whenever the persisted
  order is mutated.

  The address field is still rendered inside the parent's `<.form>`, so that
  submitting step 3 carries the delivery_address value along with the other
  step-3 fields. What the component owns is the feedback loop around the
  field — loading spinner, success check, inline errors — not the form
  submission.
  """
  use EdenflowersWeb, :live_component

  import EdenflowersWeb.CoreComponents

  alias Edenflowers.Store.Order

  @impl true
  def mount(socket) do
    {:ok, assign(socket, loading: false)}
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
        # Sync the typed address into the parent form's params so that errors
        # from the async result render on the field even if phx-change hasn't
        # fired yet.
        send(self(), {:address_typed, address})

        actor = socket.assigns.actor

        # start_async with the same name cancels any in-flight geocode, so the
        # final blur wins when the user types fast.
        {:noreply,
         socket
         |> assign(loading: true)
         |> start_async(:confirm_delivery_address, fn ->
           Order.confirm_delivery_address(order, address, actor: actor)
         end)}
    end
  end

  @impl true
  def handle_async(:confirm_delivery_address, {:ok, {:ok, order}}, socket) do
    send(self(), {:address_changed, order})
    {:noreply, assign(socket, loading: false, order: order)}
  end

  def handle_async(:confirm_delivery_address, {:ok, {:error, %Ash.Error.Invalid{} = error}}, socket) do
    {:noreply, fail(socket, error)}
  end

  # Only reachable if the async function returns a non-Ash error —
  # ConfirmDeliveryAddress wraps all its errors as Ash.Error.Invalid.
  def handle_async(:confirm_delivery_address, {:ok, {:error, _}}, socket) do
    {:noreply, fail(socket, generic_error())}
  end

  # Cancelled by a newer start_async with the same name — ignore, the new
  # task will deliver the user-facing result.
  def handle_async(:confirm_delivery_address, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, socket}
  end

  def handle_async(:confirm_delivery_address, {:exit, reason}, socket) do
    require Logger
    Logger.error("confirm_delivery_address task exited: #{inspect(reason)}")
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

    send(self(), {:address_geocode_failed, order, error})
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
