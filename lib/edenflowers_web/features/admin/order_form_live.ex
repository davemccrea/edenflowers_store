defmodule EdenflowersWeb.Admin.OrderFormLive do
  @moduledoc """
  Where Jennie enters a custom order (`:new`), and edits any open order
  after it is placed (`:edit`), online or custom, paid or not.
  """
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  require Ash.Query
  require Logger

  alias Edenflowers.Catalog.{Product, ProductVariant}
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.{Availability, DeliveryError, Fee}
  alias Edenflowers.Orders
  alias Edenflowers.Orders.{EnteredLineItems, Order}
  alias Edenflowers.Pricing
  alias Edenflowers.Pricing.TaxRate
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case load(params, actor) do
      {:ok, mode, order} ->
        tax_rates = tax_rates(order, actor)

        {:ok,
         socket
         |> assign(:mode, mode)
         |> assign(:order, order)
         |> assign(:page_title, page_title(mode, order))
         |> assign(:locale, Localize.get_locale())
         |> assign(:fulfillment_options, Fulfillment.list_options!(actor: actor))
         |> assign(:variant_options, variant_options(actor))
         |> assign(:tax_rates, tax_rates)
         |> assign(:default_tax_rate_id, default_tax_rate_id(tax_rates, actor))
         |> assign(:lines, initial_lines(mode, order, tax_rates))
         |> assign(:form, build_form(mode, order, actor))
         |> assign(:delivery_quote, stored_quote(mode, order))
         |> assign_date_warning()}

      {:error, message} ->
        {:ok,
         socket
         |> put_flash(:error, message)
         |> push_navigate(to: back_path(params))}
    end
  end

  defp load(%{"id" => id}, actor) do
    case Orders.get_order_for_admin(id, actor: actor, load: [:free_delivery?, line_items: [:subtotal]]) do
      {:ok, %Order{} = order} -> edit_mode(order)
      _ -> {:error, ~t"Order not found."}
    end
  end

  defp load(_params, _actor), do: {:ok, :new, nil}

  defp edit_mode(%{fulfillment_status: status}) when status != :pending,
    do: {:error, ~t"This order is no longer open, so it can't be changed."}

  defp edit_mode(order), do: {:ok, :edit, order}

  defp page_title(:new, _order), do: ~t"New custom order"
  defp page_title(_mode, order), do: ~t"Edit order #{reference = order.order_reference}"

  defp back_path(%{"id" => id}), do: ~p"/admin/orders/#{id}"
  defp back_path(_params), do: ~p"/admin/orders"

  defp build_form(:new, _order, actor) do
    Order
    |> AshPhoenix.Form.for_create(:place_custom,
      actor: actor,
      params: %{"locale" => "sv-FI", "payment_link?" => "true", "email_customer?" => "true"},
      transform_params: &transform_params/3
    )
    |> to_form()
  end

  defp build_form(:edit, order, actor) do
    order
    |> AshPhoenix.Form.for_update(:edit, actor: actor, transform_params: &transform_params/3)
    |> to_form()
  end

  # The browser sends the lines as an index-keyed map; the action takes a list.
  # Submit runs this again over params it has already transformed.
  # Removing the last line leaves no line_items key at all, hence the default.
  defp transform_params(_form, params, _action) do
    params
    |> Map.update("line_items", [], &lines_from_params/1)
    |> Map.update("fulfillment_fee_override", nil, &decimal_comma/1)
  end

  defp lines_from_params(lines) when is_list(lines), do: lines

  defp lines_from_params(lines) when is_map(lines) do
    lines
    |> Enum.sort_by(fn {index, _line} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, line} -> line end)
  end

  defp lines_from_params(_lines), do: []

  defp decimal_comma(value) when is_binary(value), do: String.replace(value, ",", ".")
  defp decimal_comma(value), do: value

  defp initial_lines(:new, _order, _tax_rates), do: []

  defp initial_lines(:edit, order, tax_rates) do
    Enum.map(order.line_items, fn
      %{product_variant_id: nil} = line_item ->
        %{
          "kind" => "custom",
          "description" => line_item.product_name,
          "unit_price" => Decimal.to_string(line_item.unit_price, :normal),
          "tax_rate_id" => tax_rate_id_for(tax_rates, line_item.tax_rate),
          "quantity" => to_string(line_item.quantity)
        }

      # Kept by id, so it keeps the price it was sold at.
      line_item ->
        %{
          "kind" => "catalogue",
          "id" => line_item.id,
          "name" => existing_line_name(line_item),
          "quantity" => to_string(line_item.quantity)
        }
    end)
  end

  defp existing_line_name(%{variant_size: nil} = line_item), do: line_item.product_name

  defp existing_line_name(line_item),
    do: "#{line_item.product_name} · #{variant_size_label(line_item.variant_size)}"

  # A line stores the percentage it was charged, not the rate it came from.
  defp tax_rate_id_for(tax_rates, percentage) do
    Enum.find_value(tax_rates, fn rate -> Decimal.equal?(rate.percentage, percentage) && rate.id end)
  end

  defp tax_rates(nil, actor), do: Pricing.list_selectable_tax_rates!(actor: actor)

  defp tax_rates(order, actor) do
    selectable = Pricing.list_selectable_tax_rates!(actor: actor)

    used_percentages =
      for %{product_variant_id: nil, tax_rate: percentage} <- order.line_items,
          do: percentage

    historical =
      TaxRate
      |> Ash.read!(actor: actor)
      |> Enum.filter(fn rate -> Enum.any?(used_percentages, &Decimal.equal?(&1, rate.percentage)) end)

    Enum.uniq_by(selectable ++ historical, & &1.id)
  end

  defp variant_options(actor) do
    ProductVariant
    |> Ash.Query.load(:product)
    |> Ash.read!(actor: actor)
    |> Enum.sort_by(&{&1.product.name, &1.price})
    |> Enum.map(fn variant ->
      {"#{variant.product.name} · #{variant_size_label(variant.size)} · #{Format.currency(variant.price, Format.locale())}",
       variant.id}
    end)
  end

  # Custom items default to the rate most of the catalogue is sold at.
  defp default_tax_rate_id(tax_rates, actor) do
    selectable = MapSet.new(tax_rates, & &1.id)

    Product
    |> Ash.Query.select([:tax_rate_id])
    |> Ash.read!(actor: actor)
    |> Enum.map(& &1.tax_rate_id)
    |> Enum.filter(&MapSet.member?(selectable, &1))
    |> Enum.frequencies()
    |> Enum.max_by(fn {_id, count} -> count end, fn -> nil end)
    |> case do
      {id, _count} -> id
      nil -> tax_rates |> List.first() |> then(&(&1 && &1.id))
    end
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    option_before = current_option_id(socket.assigns)

    socket =
      socket
      |> assign(:lines, lines_from_params(params["line_items"]))
      |> assign(:form, AshPhoenix.Form.validate(socket.assigns.form, params))
      |> assign_date_warning()

    if current_option_id(socket.assigns) == option_before do
      {:noreply, socket}
    else
      {:noreply, requote_for_new_option(socket)}
    end
  end

  def handle_event("quote_delivery", %{"value" => address}, socket) do
    {:noreply, quote_delivery(socket, address, current_option_id(socket.assigns))}
  end

  def handle_event("add_line", %{"kind" => "catalogue"}, socket) do
    {:noreply, update(socket, :lines, &(&1 ++ [%{"kind" => "catalogue", "quantity" => "1"}]))}
  end

  def handle_event("add_line", %{"kind" => "custom"}, socket) do
    line = %{"kind" => "custom", "quantity" => "1", "tax_rate_id" => socket.assigns.default_tax_rate_id}
    {:noreply, update(socket, :lines, &(&1 ++ [line]))}
  end

  def handle_event("remove_line", %{"index" => index}, socket) do
    {:noreply, update(socket, :lines, &List.delete_at(&1, String.to_integer(index)))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    socket = assign(socket, :lines, lines_from_params(params["line_items"]))

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, order} ->
        {:noreply,
         socket
         |> put_flash(:info, saved_message(socket.assigns.mode))
         |> push_navigate(to: ~p"/admin/orders/#{order.id}")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, ~t"The order wasn't saved. Check the fields marked below.")}
    end
  end

  # Priced as soon as the address is typed, so Jennie can tell a caller what
  # delivery costs. Saving prices it again: this quote is only for her to read.
  defp quote_delivery(socket, address, option_id) do
    address = String.trim(address || "")

    cond do
      address == "" or is_nil(option_id) ->
        assign(socket, :delivery_quote, nil)

      quoted?(socket.assigns.delivery_quote, address, option_id) ->
        socket

      true ->
        # A newer lookup with the same name cancels one still in flight.
        socket
        |> assign(:delivery_quote, %{status: :loading, address: address, option_id: option_id})
        |> start_async(:delivery_quote, fn ->
          {address, option_id, Fulfillment.calculate_delivery(address, option_id, authorize?: false)}
        end)
    end
  end

  defp requote_for_new_option(socket) do
    if selected_method(socket.assigns.form, socket.assigns.fulfillment_options, socket.assigns.order) == :delivery do
      quote_delivery(socket, socket.assigns.form[:delivery_address].value, current_option_id(socket.assigns))
    else
      assign(socket, :delivery_quote, nil)
    end
  end

  defp quoted?(%{address: address, option_id: option_id}, address, option_id), do: true
  defp quoted?(_quote, _address, _option_id), do: false

  defp current_option_id(%{form: form, order: order}) do
    form[:fulfillment_option_id].value || (order && order.fulfillment_option_id)
  end

  @impl true
  def handle_async(:delivery_quote, {:ok, {address, option_id, {:ok, %{error: nil} = result}}}, socket) do
    quote = %{
      status: :ok,
      address: address,
      option_id: option_id,
      fee: result.fulfillment_fee,
      in_free_delivery_zone: result.in_free_delivery_zone,
      distance: result.distance
    }

    {:noreply, assign(socket, :delivery_quote, quote)}
  end

  def handle_async(:delivery_quote, {:ok, {address, option_id, {:ok, %{error: reason}}}}, socket) do
    quote = %{status: :error, address: address, option_id: option_id, message: DeliveryError.message(reason)}
    {:noreply, assign(socket, :delivery_quote, quote)}
  end

  def handle_async(:delivery_quote, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:delivery_quote, result, socket) do
    Logger.error("Delivery quote failed: #{inspect(result)}")
    {address, option_id} = {socket.assigns.delivery_quote.address, socket.assigns.delivery_quote.option_id}
    quote = %{status: :error, address: address, option_id: option_id, message: DeliveryError.message(:unknown)}
    {:noreply, assign(socket, :delivery_quote, quote)}
  end

  # An order already priced by distance can be quoted again without geocoding.
  defp stored_quote(:edit, %{fulfillment_method: :delivery, distance: distance} = order)
       when is_integer(distance) do
    case Fulfillment.get_option_by_id(order.fulfillment_option_id, authorize?: false) do
      {:ok, option} ->
        case Fee.calculate(option, distance) do
          %{error: nil} = fee ->
            %{
              status: :ok,
              address: order.delivery_address,
              option_id: option.id,
              fee: fee.fulfillment_fee,
              in_free_delivery_zone: fee.in_free_delivery_zone,
              distance: distance
            }

          _out_of_range ->
            nil
        end

      _ ->
        nil
    end
  end

  defp stored_quote(_mode, _order), do: nil

  # ponytail: charged on the lines the order was saved with, not the lines in
  # the form; saving prices the new lines. Track the form's lines if Jennie misreads it.
  defp charge(%{status: :ok} = quote, order) do
    free_delivery? = !!(order && order.free_delivery?)
    %{quote | fee: Orders.charged_fulfillment_fee!(quote.fee, quote.in_free_delivery_zone, free_delivery?)}
  end

  defp charge(quote, _order), do: quote

  # A quote for an address or option no longer in the form says nothing.
  defp current_quote(quote, form, option_id) do
    address = String.trim(form[:delivery_address].value || "")
    if quoted?(quote, address, option_id), do: quote
  end

  defp saved_message(:new), do: ~t"Order placed."
  defp saved_message(_mode), do: ~t"Order updated."

  # Jennie may book a closed day; she is told it is closed, not stopped.
  defp assign_date_warning(socket) do
    form = socket.assigns.form

    option_id =
      form[:fulfillment_option_id].value || (socket.assigns.order && socket.assigns.order.fulfillment_option_id)

    option = Enum.find(socket.assigns.fulfillment_options, &(&1.id == option_id))

    warning =
      with %{} <- option,
           {:ok, date} <- parse_date(form[:fulfillment_date].value),
           reason when reason not in [nil, :past] <-
             Availability.unavailable_reason(option, date, DateTime.now!("Europe/Helsinki")) do
        date_warning(reason)
      else
        _ -> nil
      end

    assign(socket, :date_warning, warning)
  end

  defp parse_date(%Date{} = date), do: {:ok, date}
  defp parse_date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp parse_date(_value), do: :error

  defp date_warning(:weekday_disabled), do: ~t"This weekday is normally closed for this option. Booking it anyway."
  defp date_warning(:date_disabled), do: ~t"You've closed this date in the calendar. Booking it anyway."

  defp date_warning(:same_day_delivery_disabled),
    do: ~t"Same-day isn't normally offered for this option. Booking it anyway."

  defp date_warning(:order_deadline_passed), do: ~t"Today's order deadline has passed. Booking it anyway."

  defp selected_method(form, fulfillment_options, order) do
    option_id = form[:fulfillment_option_id].value || (order && order.fulfillment_option_id)

    case Enum.find(fulfillment_options, &(&1.id == option_id)) do
      %{fulfillment_method: method} -> method
      nil -> order && order.fulfillment_method
    end
  end

  defp locale_options, do: [{"Svenska", "sv-FI"}, {"Suomi", "fi"}, {"English", "en-GB"}]

  defp payment_options do
    [%{name: ~t"Send a payment link", value: "true"}, %{name: ~t"Pays in person", value: "false"}]
  end

  defp tax_rate_options(tax_rates) do
    Enum.map(tax_rates, &{"#{&1.name} (#{Format.percentage(&1.percentage, Format.locale())})", &1.id})
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:method, selected_method(assigns.form, assigns.fulfillment_options, assigns.order))
      |> assign(
        :quote,
        assigns.delivery_quote |> current_quote(assigns.form, current_option_id(assigns)) |> charge(assigns.order)
      )
      |> assign(:line_error, line_error(assigns.form, assigns.lines))

    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="narrow">
        <.admin_page_header
          title={@page_title}
          back={if @order, do: ~p"/admin/orders/#{@order.id}", else: ~p"/admin/orders"}
          back_label={if @order, do: ~t"Order", else: ~t"Orders"}
        >
          <:subtitle :if={@order && @order.payment_status == :paid}>
            {~t"This order is paid. If the total changes, the order page shows the balance to collect or refund."}
          </:subtitle>
        </.admin_page_header>

        <.form for={@form} id="order-form" phx-change="validate" phx-submit="save" class="space-y-10">
          <.form_section title={~t"Customer"}>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div class="sm:col-span-2">
                <.input field={@form[:customer_name]} type="text" label={~t"Name"} class="input w-full" />
              </div>
              <.input
                field={@form[:customer_phone_number]}
                type="tel"
                label={~t"Phone"}
                class="input w-full"
                autocomplete="off"
              />
              <.input
                field={@form[:customer_email]}
                type="email"
                label={~t"Email"}
                help={~t"A phone number or an email is needed. With an email, the order shows in their account."}
                class="input w-full"
                autocomplete="off"
              />
              <.input
                field={@form[:locale]}
                type="select"
                label={~t"Language"}
                help={~t"Used for their emails and the payment page."}
                options={locale_options()}
              />
            </div>
          </.form_section>

          <.form_section title={~t"Items"}>
            <div id="order-lines" class="space-y-3">
              <.order_line
                :for={{line, index} <- Enum.with_index(@lines)}
                line={line}
                index={index}
                error={row_error(@line_error, index)}
                variant_options={@variant_options}
                tax_rate_options={tax_rate_options(@tax_rates)}
              />
              <p :if={@lines == []} class="text-base-content/65 text-sm">{~t"No items yet."}</p>
            </div>
            <.error :if={match?({nil, _message}, @line_error)}>{elem(@line_error, 1)}</.error>
            <div class="mt-4 flex flex-wrap gap-2">
              <.button type="button" phx-click="add_line" phx-value-kind="catalogue" variant="neutral" size="sm">
                <.icon name="hero-plus" class="h-4 w-4" /> {~t"Catalogue item"}
              </.button>
              <.button type="button" phx-click="add_line" phx-value-kind="custom" variant="neutral" size="sm">
                <.icon name="hero-plus" class="h-4 w-4" /> {~t"Item with your own price"}
              </.button>
            </div>
          </.form_section>

          <.form_section title={~t"Delivery or pickup"}>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input
                field={@form[:fulfillment_option_id]}
                type="select"
                label={~t"Method"}
                prompt={~t"Choose…"}
                options={Enum.map(@fulfillment_options, &{&1.name, &1.id})}
              />
              <div>
                <.input field={@form[:fulfillment_date]} type="date" label={~t"Date"} class="input w-full" />
                <div role="status">
                  <p :if={@date_warning} id="date-warning" class="text-warning-content bg-warning/15 mt-2 px-3 py-2 text-sm">
                    {@date_warning}
                  </p>
                </div>
              </div>
              <div :if={@method == :delivery} class="sm:col-span-2">
                <.input
                  field={@form[:delivery_address]}
                  type="text"
                  label={~t"Delivery address"}
                  class="input w-full"
                  phx-blur="quote_delivery"
                  loading={match?(%{status: :loading}, @quote)}
                />
                <.delivery_quote quote={@quote} override={@form[:fulfillment_fee_override].value} />
              </div>
              <div :if={@method == :delivery} class="sm:col-span-2">
                <.input
                  field={@form[:delivery_instructions]}
                  type="text"
                  label={~t"Delivery instructions"}
                  class="input w-full"
                />
              </div>
              <.input
                field={@form[:fulfillment_fee_override]}
                type="text"
                inputmode="decimal"
                label={if @method == :delivery, do: ~t"Your own delivery fee", else: ~t"Your own fee"}
                help={~t"Leave blank to calculate it as checkout would. 0 for free."}
                class="input w-full"
              />
            </div>
          </.form_section>

          <.form_section title={~t"Recipient and card"}>
            <:description>{~t"Leave the recipient blank when the flowers are for the customer."}</:description>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <.input field={@form[:recipient_name]} type="text" label={~t"Recipient"} class="input w-full" />
              <.input
                field={@form[:recipient_phone_number]}
                type="tel"
                label={if @method == :delivery, do: ~t"Recipient phone (for the delivery)", else: ~t"Recipient phone"}
                class="input w-full"
              />
              <div id="card-message-field" class="sm:col-span-2" phx-hook="CharacterCount">
                <.input
                  field={@form[:card_message]}
                  type="textarea"
                  label={~t"Card message"}
                  rows="3"
                  maxlength="200"
                />
                <p class="text-base-content/65 mt-1 text-right text-sm tabular-nums">
                  <span id="char-count">0</span>/200
                </p>
              </div>
            </div>
          </.form_section>

          <.form_section title={~t"Florist note"}>
            <:description>{~t"Only you see this: what was agreed, timings, anything to remember."}</:description>
            <.input field={@form[:florist_note]} type="textarea" rows="4" aria-label={~t"Florist note"} />
          </.form_section>

          <.form_section :if={@mode == :new} title={~t"Payment"}>
            <div class="space-y-4">
              <.input :let={option} field={@form[:payment_link?]} type="radio-card" options={payment_options()}>
                {option.name}
              </.input>
              <.input
                field={@form[:email_customer?]}
                type="checkbox"
                label={~t"Email the order details to the customer (needs an email)"}
              />
            </div>
          </.form_section>

          <div class="flex justify-end">
            <.button type="submit" variant="primary" phx-disable-with={~t"Saving…"}>
              {if @mode == :new, do: ~t"Place order", else: ~t"Save changes"}
            </.button>
          </div>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :quote, :map, default: nil
  attr :override, :any, default: nil

  defp delivery_quote(assigns) do
    ~H"""
    <div aria-live="polite">
      <p :if={match?(%{status: :ok}, @quote)} id="delivery-quote" class="mt-1.5 text-sm">
        <span class="font-medium">{~t"Delivery #{fee = Format.currency(@quote.fee, Format.locale())}"}</span>
        <span class="text-base-content/65">({Format.distance(@quote.distance, Format.locale())})</span>
        <span :if={present?(@override)} class="text-base-content/65">
          · {~t"your own fee replaces this"}
        </span>
      </p>
      <p :if={match?(%{status: :error}, @quote)} id="delivery-quote" class="text-warning-content mt-1.5 text-sm">
        {@quote.message}. {~t"You can still set your own fee."}
      </p>
    </div>
    """
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  # Errors only after the first save: the lines have no single input for
  # used_input? to track. A nil number is about the lines as a whole.
  defp line_error(form, lines) do
    if form.source.submitted_once? do
      case EnteredLineItems.parse(lines) do
        {:error, number, message} -> {number, message}
        {:ok, _lines} -> nil
      end
    end
  end

  defp row_error({number, message}, index) when number == index + 1, do: message
  defp row_error(_line_error, _index), do: nil

  attr :line, :map, required: true
  attr :index, :integer, required: true
  attr :error, :string, default: nil
  attr :variant_options, :list, required: true
  attr :tax_rate_options, :list, required: true

  # A line the order already has: its product is fixed, only how many changes.
  defp order_line(%{line: %{"kind" => "catalogue", "id" => _}} = assigns) do
    ~H"""
    <.line_row index={@index} error={@error}>
      <input type="hidden" name={"form[line_items][#{@index}][kind]"} value="catalogue" />
      <input type="hidden" name={"form[line_items][#{@index}][id]"} value={@line["id"]} />
      <input type="hidden" name={"form[line_items][#{@index}][name]"} value={@line["name"]} />
      <div class="flex min-w-0 flex-1 basis-64 flex-col text-sm">
        <span class="mb-1">{~t"Product"}</span>
        <p class="flex h-10 items-center text-base font-medium">{@line["name"]}</p>
      </div>
      <.quantity_input index={@index} value={@line["quantity"]} error={@error} />
      <.remove_line_button index={@index} />
    </.line_row>
    """
  end

  defp order_line(%{line: %{"kind" => "catalogue"}} = assigns) do
    ~H"""
    <.line_row index={@index} error={@error}>
      <input type="hidden" name={"form[line_items][#{@index}][kind]"} value="catalogue" />
      <label class="flex min-w-0 flex-1 basis-64 flex-col text-sm">
        <span class="mb-1">{~t"Product"}</span>
        <select
          name={"form[line_items][#{@index}][product_variant_id]"}
          class={["select w-full", @error && "select-error"]}
          {error_attrs(@index, @error)}
        >
          <option value="">{~t"Choose…"}</option>
          {Phoenix.HTML.Form.options_for_select(@variant_options, @line["product_variant_id"])}
        </select>
      </label>
      <.quantity_input index={@index} value={@line["quantity"]} error={@error} />
      <.remove_line_button index={@index} />
    </.line_row>
    """
  end

  defp order_line(assigns) do
    ~H"""
    <.line_row index={@index} error={@error}>
      <input type="hidden" name={"form[line_items][#{@index}][kind]"} value="custom" />
      <label class="flex min-w-0 flex-1 basis-full flex-col text-sm">
        <span class="mb-1">{~t"Description"}</span>
        <input
          type="text"
          name={"form[line_items][#{@index}][description]"}
          value={@line["description"]}
          placeholder={~t"e.g. Funeral spray, white roses"}
          class={["input w-full", @error && "input-error"]}
          {error_attrs(@index, @error)}
        />
      </label>
      <label class="flex w-32 flex-col text-sm">
        <span class="mb-1">{~t"Price each (€)"}</span>
        <input
          type="text"
          inputmode="decimal"
          name={"form[line_items][#{@index}][unit_price]"}
          value={@line["unit_price"]}
          class={["input w-full tabular-nums", @error && "input-error"]}
          {error_attrs(@index, @error)}
        />
      </label>
      <label class="flex min-w-0 flex-1 basis-40 flex-col text-sm">
        <span class="mb-1">{~t"VAT"}</span>
        <select name={"form[line_items][#{@index}][tax_rate_id]"} class="select w-full">
          {Phoenix.HTML.Form.options_for_select(@tax_rate_options, @line["tax_rate_id"])}
        </select>
      </label>
      <.quantity_input index={@index} value={@line["quantity"]} error={@error} />
      <.remove_line_button index={@index} />
    </.line_row>
    """
  end

  attr :index, :integer, required: true
  attr :error, :string, default: nil
  slot :inner_block, required: true

  # Numbered, so "Item 2: enter a price" points at a row Jennie can see.
  defp line_row(assigns) do
    ~H"""
    <fieldset
      class={["border p-3", if(@error, do: "border-error", else: "border-base-content/12")]}
      data-testid="order-line"
    >
      <legend class="text-base-content/65 px-1 text-xs">{~t"Item #{number = @index + 1}"}</legend>
      <div class="flex flex-wrap items-end gap-3">
        {render_slot(@inner_block)}
      </div>
      <p :if={@error} id={"line-#{@index}-error"} class="text-error mt-2 text-sm">{@error}</p>
    </fieldset>
    """
  end

  defp error_attrs(_index, nil), do: []
  defp error_attrs(index, _error), do: ["aria-invalid": "true", "aria-describedby": "line-#{index}-error"]

  attr :index, :integer, required: true
  attr :value, :any, required: true
  attr :error, :string, default: nil

  defp quantity_input(assigns) do
    ~H"""
    <label class="flex w-20 flex-col text-sm">
      <span class="mb-1">{~t"Qty"}</span>
      <input
        type="number"
        min="1"
        name={"form[line_items][#{@index}][quantity]"}
        value={@value}
        class={["input w-full tabular-nums", @error && "input-error"]}
        {error_attrs(@index, @error)}
      />
    </label>
    """
  end

  attr :index, :integer, required: true

  defp remove_line_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="remove_line"
      phx-value-index={@index}
      class="btn btn-ghost btn-square text-error size-10"
      aria-label={~t"Remove item #{number = @index + 1}"}
    >
      <.icon name="hero-trash" class="h-4 w-4" />
    </button>
    """
  end
end
