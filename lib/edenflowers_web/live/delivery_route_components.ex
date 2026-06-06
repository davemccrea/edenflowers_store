defmodule EdenflowersWeb.DeliveryRouteComponents do
  @moduledoc """
  Mobile-first rendering for the shared delivery route page: the ordered day with
  derived return-to-shop rows, per-stop detail, the Google Maps link, and the
  daisyUI outcome dialog. Used by both the public driver page and the admin
  monitoring page.
  """
  use EdenflowersWeb, :html

  import EdenflowersWeb.DeliveryRouteShared,
    only: [
      delivered?: 1,
      cancelled?: 1,
      maps_url: 1,
      shop_maps_url: 0,
      latest_failed_attempt: 1
    ]

  alias Edenflowers.Format

  attr :route, :any, required: true
  attr :rows, :list, required: true
  attr :complete?, :boolean, required: true
  attr :expired?, :boolean, default: false
  attr :active_stop, :any, default: nil
  attr :outcome, :string, default: "delivered"
  attr :locale, :string, required: true

  def route_page(assigns) do
    ~H"""
    <div class="mx-auto max-w-xl px-4 py-6">
      <header class="mb-6">
        <h1 class="text-xl font-semibold">{@route.driver.name}</h1>
        <p class="text-base-content/60 text-sm">{Format.weekday_day_month(@route.delivery_date, @locale)}</p>
      </header>

      <div :if={@expired?} class="alert alert-warning mb-4">
        <.icon name="hero-clock" class="h-5 w-5" />
        <span>{~t"This route has expired. Updates are no longer accepted."}</span>
      </div>

      <div :if={@complete? and not @expired?} class="alert alert-success mb-4">
        <.icon name="hero-check-circle" class="h-5 w-5" />
        <span>{~t"Route complete"}</span>
      </div>

      <ol class="space-y-3">
        <li :for={row <- @rows}>
          <.row row={row} expired?={@expired?} />
        </li>
      </ol>

      <.outcome_dialog :if={@active_stop} stop={@active_stop} outcome={@outcome} />
    </div>
    """
  end

  attr :row, :any, required: true
  attr :expired?, :boolean, required: true

  defp row(%{row: {:return, _leg}} = assigns) do
    %{row: {:return, leg}} = assigns
    assigns = assign(assigns, :leg, leg)

    ~H"""
    <div class="border-base-300 bg-base-200/40 rounded-lg border border-dashed p-3">
      <div class="flex items-center justify-between gap-2">
        <span class="inline-flex items-center gap-2 text-sm font-medium">
          <.icon name="hero-arrow-uturn-left" class="text-base-content/60 h-4 w-4" />
          {~t"Return to shop"}
        </span>
        <a href={shop_maps_url()} target="_blank" rel="noopener" class="btn btn-xs btn-outline">
          <.icon name="hero-map" class="h-3.5 w-3.5" />
          {~t"Navigate"}
        </a>
      </div>
      <p class="text-base-content/50 mt-1 text-xs">
        {Format.km(@leg.distance)} · {Format.minutes(@leg.duration)}
      </p>
    </div>
    """
  end

  defp row(%{row: {:stop, stop}} = assigns) do
    assigns = assign(assigns, :stop, stop)

    cond do
      cancelled?(assigns.stop) -> cancelled_stop(assigns)
      delivered?(assigns.stop) -> delivered_stop(assigns)
      true -> pending_stop(assigns)
    end
  end

  defp cancelled_stop(assigns) do
    ~H"""
    <div class="border-base-300/70 rounded-lg border p-3 opacity-70">
      <div class="flex items-center justify-between">
        <span class="text-sm font-medium line-through">{@stop.order.order_reference}</span>
        <span class="badge badge-sm badge-warning">{~t"Cancelled - do not deliver"}</span>
      </div>
    </div>
    """
  end

  defp delivered_stop(assigns) do
    ~H"""
    <div class="border-base-300/70 rounded-lg border p-3 opacity-70">
      <div class="flex items-center justify-between">
        <span class="text-sm font-medium line-through">
          {@stop.order.order_reference} · {@stop.order.recipient_name}
        </span>
        <span class="badge badge-sm badge-success">{~t"Delivered"}</span>
      </div>
    </div>
    """
  end

  defp pending_stop(assigns) do
    assigns =
      assigns
      |> assign(:products, products(assigns.stop))
      |> assign(:failed, latest_failed_attempt(assigns.stop))

    ~H"""
    <div class="border-base-300 bg-base-100 rounded-lg border p-4">
      <div class="mb-2 flex items-start justify-between gap-2">
        <span class="text-sm font-semibold">{@stop.order.order_reference}</span>
        <span class="text-base-content/50 whitespace-nowrap text-xs">
          {Format.km(@stop.leg_distance)} · {Format.minutes(@stop.leg_duration)}
        </span>
      </div>

      <div class="space-y-2 text-sm">
        <p class="font-medium">{@stop.order.recipient_name}</p>

        <a
          :if={@stop.order.recipient_phone_number}
          href={"tel:#{@stop.order.recipient_phone_number}"}
          class="text-primary inline-flex items-center gap-1.5"
        >
          <.icon name="hero-phone" class="h-4 w-4" />
          {@stop.order.recipient_phone_number}
        </a>

        <p class="text-base-content/80">{@stop.order.delivery_address}</p>

        <p :if={@stop.order.delivery_instructions} class="text-base-content/70">
          <span class="font-medium">{~t"Instructions"}:</span> {@stop.order.delivery_instructions}
        </p>

        <div :if={@stop.order.card_message} class="bg-base-200/60 rounded p-2">
          <span class="text-base-content/60 block text-xs font-medium uppercase">{~t"Card message"}</span>
          <p class="whitespace-pre-line">{@stop.order.card_message}</p>
        </div>

        <ul :if={@products != []} class="text-base-content/80 list-inside list-disc">
          <li :for={item <- @products}>
            {item.quantity}× {item.product_name}
            <%= if item.variant_size do %>
              ({item.variant_size})
            <% end %>
          </li>
        </ul>

        <div :if={@failed} class="alert alert-warning py-2 text-xs">
          <span>
            {~t"Last attempt failed"}: {failure_reason_label(@failed.failure_reason)}
            <%= if @failed.note do %>
              — {@failed.note}
            <% end %>
          </span>
        </div>
      </div>

      <div class="mt-3 flex flex-wrap gap-2">
        <a
          href={maps_url(@stop.order.position)}
          target="_blank"
          rel="noopener"
          class="btn btn-sm btn-outline"
        >
          <.icon name="hero-map" class="h-4 w-4" />
          {~t"Navigate"}
        </a>
        <button
          :if={not @expired?}
          class="btn btn-sm btn-primary"
          phx-click="open_outcome"
          phx-value-stop-id={@stop.id}
        >
          {~t"Record outcome"}
        </button>
      </div>
    </div>
    """
  end

  attr :stop, :any, required: true
  attr :outcome, :string, required: true

  defp outcome_dialog(assigns) do
    ~H"""
    <dialog class="modal modal-open" phx-window-keydown="close_outcome" phx-key="Escape">
      <div class="modal-box">
        <h3 class="mb-4 text-lg font-semibold">
          {~t"Record outcome"} — {@stop.order.order_reference}
        </h3>

        <form phx-submit="record_outcome" phx-change="change_outcome" class="space-y-4">
          <div class="join w-full">
            <input
              type="radio"
              name="outcome"
              value="delivered"
              class="join-item btn btn-sm flex-1"
              aria-label={~t"Delivered"}
              checked={@outcome == "delivered"}
            />
            <input
              type="radio"
              name="outcome"
              value="failed"
              class="join-item btn btn-sm flex-1"
              aria-label={~t"Failed"}
              checked={@outcome == "failed"}
            />
          </div>

          <label :if={@outcome == "delivered"} class="form-control">
            <span class="label-text mb-1">{~t"Method"}</span>
            <select name="delivered_method" class="select select-bordered select-sm">
              <option value="handed_to_recipient">{~t"Handed to recipient"}</option>
              <option value="left_in_safe_place">{~t"Left in a safe place"}</option>
              <option value="other">{~t"Other"}</option>
            </select>
          </label>

          <label :if={@outcome == "failed"} class="form-control">
            <span class="label-text mb-1">{~t"Reason"}</span>
            <select name="failure_reason" class="select select-bordered select-sm">
              <option value="recipient_unavailable">{~t"Recipient unavailable"}</option>
              <option value="could_not_access_address">{~t"Could not access address"}</option>
              <option value="could_not_find_address">{~t"Could not find address"}</option>
              <option value="recipient_refused">{~t"Recipient refused delivery"}</option>
              <option value="other">{~t"Other"}</option>
            </select>
          </label>

          <label class="form-control">
            <span class="label-text mb-1">{~t"Note"}</span>
            <textarea name="note" rows="2" class="textarea textarea-bordered textarea-sm"></textarea>
          </label>

          <div class="modal-action">
            <button type="button" class="btn btn-sm btn-ghost" phx-click="close_outcome">
              {~t"Cancel"}
            </button>
            <button type="submit" class="btn btn-sm btn-primary">{~t"Save"}</button>
          </div>
        </form>
      </div>
    </dialog>
    """
  end

  defp products(stop) do
    stop.order.line_items
    |> Enum.reject(& &1.is_card)
  end

  defp failure_reason_label(:recipient_unavailable), do: ~t"Recipient unavailable"
  defp failure_reason_label(:could_not_access_address), do: ~t"Could not access address"
  defp failure_reason_label(:could_not_find_address), do: ~t"Could not find address"
  defp failure_reason_label(:recipient_refused), do: ~t"Recipient refused delivery"
  defp failure_reason_label(:other), do: ~t"Other"
  defp failure_reason_label(_), do: ~t"Failed"
end
