defmodule EdenflowersWeb.Checkout.AddressInput do
  @moduledoc """
  Delivery address input with asynchronous geocoding on blur.

  Geocoding runs on blur for the visual feedback ("Delivery 5,00 € (3,0 km)") but
  the result is *not* trusted by the server. On submit, `submit_delivery`
  re-derives `geocoded_address`, `position`, `here_id`, `distance`, and
  `fulfillment_fee` server-side via `CalculateFulfillmentCost`, so a
  client cannot inject those values.

  Error display is component-owned. `{:required, _}` is raised the
  instant the user empties the field. Blur-time API errors set
  `{:api, _}` directly. On submit-time failures, the parent forwards the
  `delivery_address` field error via `send_update(__MODULE__, id:
  "address-input", error_message: msg)` so the message renders next to
  the field instead of at the form root.

  The parent owns the quote (`%{address: ..., distance: ...}`) and the fee
  priced from it, so the order summary and this field always agree. A lookup
  sends `{:delivery_quoted, quote}` to the parent, and `nil` when the quote
  no longer describes the typed address. The quote never touches the form.
  """
  use EdenflowersWeb, :live_component
  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Logger
  import EdenflowersWeb.CoreComponents

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.DeliveryError

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
        label={@label}
        type="text"
        autocomplete={@autocomplete}
        aria-required="true"
        errors={errors(@error, @touched)}
        phx-change="typing"
        phx-blur="lookup_address"
        phx-target={@myself}
        loading={@loading}
        confirmed={confirmed?(@typed, @quote, @loading)}
      />
      <div aria-live="polite">
        <p
          :if={confirmed?(@typed, @quote, @loading)}
          data-testid="address-distance"
          class="mt-1.5 text-sm"
        >
          <span class={free?(@fee) && "text-success"}>
            {format_delivery_amount(@fee, @order)}
          </span>
          <span class="text-base-content/65">
            ({Edenflowers.Format.distance(@quote.distance, @order.locale)})
          </span>
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("typing", %{"delivery_address" => value}, socket) do
    quote = socket.assigns.quote
    if quote && value != quote.address, do: send(self(), {:delivery_quoted, nil})

    error =
      if String.trim(value) == "",
        do: {:required, DeliveryError.message(:address_required)},
        else: nil

    {:noreply, assign(socket, typed: value, touched: true, error: error)}
  end

  def handle_event("lookup_address", %{"value" => address}, socket) do
    quote = socket.assigns.quote

    cond do
      String.trim(address) == "" ->
        {:noreply, socket}

      quote && address == quote.address ->
        {:noreply, socket}

      true ->
        fulfillment_option = socket.assigns.order.fulfillment_option

        # start_async with the same name cancels any in-flight lookup, so the
        # final blur wins when the user types fast.
        {:noreply,
         socket
         |> assign(loading: true, typed: address, error: nil)
         |> start_async(:lookup_address, fn ->
           Fulfillment.calculate_delivery(address, fulfillment_option.id)
         end)}
    end
  end

  @impl true
  def handle_async(:lookup_address, {:ok, {:ok, result}}, socket) do
    if result.error do
      {:noreply, fail(socket, DeliveryError.message(result.error))}
    else
      send(self(), {:delivery_quoted, %{address: socket.assigns.typed, distance: result.distance}})
      {:noreply, assign(socket, loading: false, error: nil)}
    end
  end

  def handle_async(:lookup_address, {:exit, {:shutdown, :cancel}}, socket) do
    {:noreply, socket}
  end

  def handle_async(:lookup_address, result, socket) do
    Logger.error("lookup_address unexpected result: #{inspect(result)}")
    {:noreply, fail(socket, DeliveryError.message(:unknown))}
  end

  defp fail(socket, message) do
    send(self(), {:delivery_quoted, nil})
    assign(socket, loading: false, error: {:api, message})
  end

  defp confirmed?(typed, quote, loading) do
    not loading and not is_nil(quote) and typed == quote.address
  end

  # Matches Phoenix's used_input? semantics: an untouched field shows no
  # error even if it's invalid. {:required, _} only shows after the user
  # has interacted; {:api, _} always shows (the user just triggered the
  # API call, so the field is implicitly touched).
  defp errors({:required, _}, false), do: []
  defp errors({_kind, message}, _touched), do: [message]
  defp errors(nil, _touched), do: []

  defp format_delivery_amount(nil, _order), do: ""

  defp format_delivery_amount(amount, order) do
    if free?(amount),
      do: ~t"Free delivery!",
      else: ~t"Delivery #{fee = Edenflowers.Format.currency(amount, order.locale)}"
  end

  defp free?(nil), do: false
  defp free?(amount), do: Decimal.eq?(amount, 0)
end
