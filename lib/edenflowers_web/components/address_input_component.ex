defmodule EdenflowersWeb.AddressInputComponent do
  @moduledoc """
  Delivery address input with asynchronous geocoding on blur.

  Geocoding runs on blur for the visual feedback ("3.0 km • 5.00") but
  the result is *not* trusted by the server. On submit, `submit_delivery`
  re-derives `geocoded_address`, `position`, `here_id`, `distance`, and
  `fulfillment_amount` server-side via `CalculateFulfillmentCost`, so a
  client cannot inject those values.

  Error display is component-owned. `{:required, _}` is raised the
  instant the user empties the field. Blur-time API errors set
  `{:api, _}` directly. On submit-time failures, the parent forwards the
  `delivery_address` field error via `send_update(__MODULE__, id:
  "address-input", error_message: msg)` so the message renders next to
  the field instead of at the form root.
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
  def update(%{error_message: message}, socket) when is_binary(message) do
    {:ok, assign(socket, error: {:api, message}, touched: true)}
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

    socket =
      if confirmed && value != confirmed.address do
        assign(socket, confirmed: nil)
      else
        socket
      end

    error =
      if String.trim(value) == "",
        do: {:required, Fulfillments.delivery_error_message(:address_required)},
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

    {:noreply,
     assign(socket,
       loading: false,
       confirmed: %{address: address, result: result},
       error: nil
     )}
  end

  def handle_async(:lookup_address, {:ok, {:error, reason}}, socket) do
    {:noreply, fail(socket, Fulfillments.delivery_error_message(reason))}
  end

  def handle_async(:lookup_address, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, socket}
  end

  def handle_async(:lookup_address, result, socket) do
    Logger.error("lookup_address unexpected result: #{inspect(result)}")
    {:noreply, fail(socket, Fulfillments.delivery_error_message(:unknown))}
  end

  defp fail(socket, message) do
    assign(socket, loading: false, confirmed: nil, error: {:api, message})
  end

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
