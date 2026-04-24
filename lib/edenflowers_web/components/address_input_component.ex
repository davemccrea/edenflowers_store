defmodule EdenflowersWeb.AddressInputComponent do
  @moduledoc """
  Delivery address input with asynchronous geocoding on blur.

  Geocoding runs on blur but its result lives in this component's socket
  assigns until the parent form is submitted — the address and geocode
  attributes on `order` are only written when the user clicks Next, like
  every other checkout field.

  The component notifies the parent of geocode state via two messages:

    * `{:address_geocoded, address, result}` — a successful geocode.
      The parent stashes the result and merges it into submit params.
    * `:address_cleared` — the previously-geocoded address is no longer
      valid (field cleared, edited, fulfillment option switched, or
      geocode failed). The parent drops any stashed result.

  Error display is component-owned. `{:required, _}` is raised the
  instant the user empties the field. On submit, `ValidateGeocodedAddress`
  on `save_step_3` enforces the server-side rule; when that fails the
  parent calls `send_update(__MODULE__, id: "address-input",
  required_error: true)` so the component shows the same message where
  the user is looking.
  """
  use EdenflowersWeb, :live_component
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger
  import EdenflowersWeb.CoreComponents

  alias Edenflowers.Fulfillments

  @impl true
  def mount(socket) do
    {:ok, assign(socket, loading: false, touched: false, error: nil)}
  end

  @impl true
  def update(%{required_error: true}, socket) do
    {:ok,
     assign(socket,
       error: {:required, ~t"Delivery address required"},
       touched: true
     )}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:typed, fn -> assigns.order.delivery_address end)
      |> assign_new(:confirmed, fn -> confirmed_from_order(assigns.order) end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.input
        id="address-input-field"
        name="delivery_address"
        value={@typed}
        label={~t"Address *"}
        type="text"
        errors={errors(@error, @touched)}
        phx-change="typing"
        phx-blur="lookup_address"
        phx-target={@myself}
        loading={@loading}
        confirmed={confirmed?(@typed, @confirmed, @loading)}
      />
      <p
        :if={confirmed?(@typed, @confirmed, @loading)}
        data-testid="address-distance"
        class="mt-1.5 text-sm"
      >
        {format_distance(@confirmed.result.distance)} • {format_delivery_amount(@confirmed.result.fulfillment_amount)}
      </p>
    </div>
    """
  end

  @impl true
  def handle_event("typing", %{"delivery_address" => value}, socket) do
    confirmed = socket.assigns.confirmed

    # When the user diverges from a previously confirmed address, drop the
    # cached result so submit can't sneak through on a stale result.
    socket =
      if confirmed && value != confirmed.address do
        send(self(), :address_cleared)
        assign(socket, confirmed: nil)
      else
        socket
      end

    error =
      if String.trim(value) == "",
        do: {:required, ~t"Delivery address required"},
        else: nil

    {:noreply, assign(socket, typed: value, touched: true, error: error)}
  end

  def handle_event("lookup_address", %{"value" => address}, socket) do
    confirmed = socket.assigns.confirmed

    cond do
      String.trim(address) == "" ->
        {:noreply, socket}

      confirmed && address == confirmed.address ->
        {:noreply, socket}

      true ->
        fulfillment_option = socket.assigns.order.fulfillment_option

        # start_async with the same name cancels any in-flight lookup, so the
        # final blur wins when the user types fast.
        {:noreply,
         socket
         |> assign(loading: true, typed: address, error: nil)
         |> start_async(:lookup_address, fn ->
           Fulfillments.calculate_delivery(address, fulfillment_option)
         end)}
    end
  end

  @impl true
  def handle_async(:lookup_address, {:ok, {:ok, result}}, socket) do
    address = socket.assigns.typed
    send(self(), {:address_geocoded, address, result})

    {:noreply,
     assign(socket,
       loading: false,
       confirmed: %{address: address, result: result},
       error: nil
     )}
  end

  def handle_async(:lookup_address, {:ok, {:error, reason}}, socket) do
    {:noreply, fail(socket, message_for(reason))}
  end

  def handle_async(:lookup_address, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, socket}
  end

  def handle_async(:lookup_address, result, socket) do
    Logger.error("lookup_address unexpected result: #{inspect(result)}")
    {:noreply, fail(socket, ~t"There was a problem calculating delivery cost, please try again later")}
  end

  defp fail(socket, message) do
    if socket.assigns.confirmed, do: send(self(), :address_cleared)
    assign(socket, loading: false, confirmed: nil, error: {:api, message})
  end

  defp message_for(:address_not_found), do: ~t"Address not found"
  defp message_for(:out_of_delivery_range), do: ~t"Outside delivery range"
  defp message_for(_), do: ~t"There was a problem calculating delivery cost, please try again later"

  # If the order already has a persisted geocode (e.g. user navigated back
  # from step 4), reflect it as confirmed so the check icon and delivery
  # summary render without re-geocoding.
  defp confirmed_from_order(%{delivery_address: address, geocoded_address: geocoded} = order)
       when is_binary(address) and is_binary(geocoded) do
    %{
      address: address,
      result: %{
        geocoded_address: geocoded,
        position: order.position,
        here_id: order.here_id,
        distance: order.distance,
        fulfillment_amount: order.fulfillment_amount
      }
    }
  end

  defp confirmed_from_order(_), do: nil

  defp confirmed?(typed, confirmed, loading) do
    not loading and not is_nil(confirmed) and typed == confirmed.address
  end

  # Matches Phoenix's used_input? semantics: an untouched field shows no
  # error even if it's invalid. {:required, _} only shows after the user
  # has interacted; {:api, _} always shows (the user just triggered the
  # API call, so the field is implicitly touched).
  defp errors({:required, _}, false), do: []
  defp errors({_kind, message}, _touched), do: [message]
  defp errors(nil, _touched), do: []

  defp format_distance(nil), do: ""

  defp format_distance(meters) when is_integer(meters) do
    km = meters / 1000
    if km < 1, do: "#{meters} m", else: "#{:erlang.float_to_binary(km, decimals: 1)} km"
  end

  defp format_delivery_amount(nil), do: ""

  defp format_delivery_amount(amount) do
    if Decimal.eq?(amount, 0), do: ~t"Free delivery! 🥳", else: Edenflowers.Utils.format_money(amount)
  end
end
