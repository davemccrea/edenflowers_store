defmodule EdenflowersWeb.Checkout.AddressInput do
  @moduledoc """
  Delivery address input with asynchronous geocoding on blur or form submit.

  Geocoding runs on blur so the order summary can price the address, but
  the result is *not* trusted by the server. On submit, `submit_delivery`
  re-derives `geocoded_address`, `position`, `here_id`, `distance`, and
  `fulfillment_fee` server-side via `CalculateFulfillmentCost`, so a
  client cannot inject those values.

  Error display is component-owned. `{:required, _}` is raised the
  instant the user empties a required field; optional fields stay quiet
  unless an empty lookup is explicitly submitted. Blur-time API errors set
  `{:api, _}` directly. On submit-time failures, the parent forwards the
  `delivery_address` field error via `send_update(__MODULE__, id:
  "address-input", error_message: msg)` so the message renders next to
  the field instead of at the form root.

  The resolved address is shown under the field so the customer can catch
  HERE matching the wrong place. It is never written back into the field:
  HERE drops flat numbers and stair codes the courier needs.

  The parent supplies `address` and `fulfillment_option` and owns the quote
  (the typed address, resolved address, distance, fee and free-delivery eligibility). A lookup
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
    {:ok,
     assign(socket,
       loading: false,
       touched: false,
       error: nil,
       required: true,
       show_confirmation: true,
       show_label: true,
       lookup_on_blur: true
     )}
  end

  @impl true
  def update(%{error_message: message}, socket) when is_binary(message) do
    {:ok, assign(socket, error: {:api, message}, touched: true)}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:typed, fn -> assigns.address end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.input
        id="address-input-field"
        name="delivery_address"
        value={@typed}
        label={if @show_label, do: @label}
        aria-label={if not @show_label, do: @label}
        type="text"
        placeholder="Myrvägen 1, 65230 Vasa"
        autocomplete={@autocomplete}
        aria-required={to_string(@required)}
        errors={errors(@error, @touched)}
        phx-change="typing"
        phx-blur={if @lookup_on_blur, do: "lookup_address"}
        phx-target={@myself}
        loading={@loading}
        confirmed={confirmed?(@typed, @quote, @loading)}
      />
      <div aria-live="polite">
        <p
          :if={@show_confirmation && confirmed?(@typed, @quote, @loading)}
          data-testid="address-confirmation"
          class="text-base-content/65 mt-1.5 text-sm"
        >
          {~t"Delivering to #{address = @quote.geocoded_address}"}
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
      if socket.assigns.required && String.trim(value) == "",
        do: {:required, DeliveryError.message(:address_required)},
        else: nil

    socket = if socket.assigns.loading, do: cancel_async(socket, :lookup_address), else: socket

    {:noreply, assign(socket, typed: value, touched: true, error: error, loading: false)}
  end

  def handle_event("lookup_address", %{"delivery_address" => address}, socket) do
    if String.trim(address) == "" do
      {:noreply, fail(socket, DeliveryError.message(:address_required))}
    else
      handle_event("lookup_address", %{"value" => address}, socket)
    end
  end

  def handle_event("lookup_address", %{"value" => address}, socket) do
    quote = socket.assigns.quote

    cond do
      String.trim(address) == "" && not socket.assigns.required ->
        send(self(), {:delivery_quoted, nil})
        socket = if socket.assigns.loading, do: cancel_async(socket, :lookup_address), else: socket
        {:noreply, assign(socket, typed: address, touched: false, error: nil, loading: false)}

      String.trim(address) == "" ->
        {:noreply, fail(socket, DeliveryError.message(:address_required))}

      quote && address == quote.address ->
        {:noreply, socket}

      true ->
        fulfillment_option = socket.assigns.fulfillment_option
        locale = Gettext.get_locale(EdenflowersWeb.Gettext)
        send(self(), {:delivery_quoted, nil})

        # start_async with the same name cancels any in-flight lookup, so the
        # final blur wins when the user types fast.
        {:noreply,
         socket
         |> assign(loading: true, typed: address, error: nil)
         |> start_async(:lookup_address, fn ->
           # The task is a new process, which doesn't inherit the Gettext
           # locale HERE's `lang` is read from.
           Gettext.put_locale(EdenflowersWeb.Gettext, locale)
           Fulfillment.calculate_delivery(address, fulfillment_option.id)
         end)}
    end
  end

  @impl true
  def handle_async(:lookup_address, {:ok, {:ok, result}}, socket) do
    if result.error do
      {:noreply, fail(socket, DeliveryError.message(result.error))}
    else
      send(
        self(),
        {:delivery_quoted,
         %{
           address: socket.assigns.typed,
           geocoded_address: result.geocoded_address,
           distance: result.distance,
           fulfillment_fee: result.fulfillment_fee,
           in_free_delivery_zone: result.in_free_delivery_zone
         }}
      )

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

  # An API error shows untouched: the user's own typing triggered the lookup.
  defp errors({:required, _}, false), do: []
  defp errors({_kind, message}, _touched), do: [message]
  defp errors(nil, _touched), do: []
end
