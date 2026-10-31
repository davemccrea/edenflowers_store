defmodule EdenflowersWeb.StoreCalendar do
  @moduledoc """
  The customer's month grid at checkout. Each day is a button sending
  `"select-date"` with its date to the LiveView. A day that isn't open is only
  marked `aria-disabled`, so the LiveView must refuse it.
  """
  use EdenflowersWeb, :html

  import EdenflowersWeb.KeyDateIcon

  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.ShopTime
  alias EdenflowersWeb.MonthGrid

  attr :id, :string, required: true
  attr :selected_date, :any, default: nil, doc: "`Date.t()`, an ISO 8601 string or nil"

  attr :calendar, :any, required: true, doc: "`ShopCalendar.t()`; only its open days can be picked"

  attr :error, :boolean, default: false

  def store_calendar(assigns) do
    assigns = assign(assigns, selected_date: parse_date(assigns.selected_date), today: ShopTime.today())

    ~H"""
    <.live_component
      module={MonthGrid}
      id={@id}
      today={@today}
      focus_date={@selected_date}
      open_date={Availability.next_open_date(@calendar, ShopTime.now())}
      status={if @selected_date, do: "#{Localize.Date.to_string!(@selected_date, format: :full)} #{~t"selected"}."}
      class={["border p-2", if(@error, do: "border-error", else: "border-base-content/20")]}
    >
      <:day :let={%{date: day, attrs: attrs}}>
        <% state = Availability.customer_cell_state(@calendar, day) %>
        <button
          {attrs}
          phx-click="select-date"
          phx-value-date={day}
          type="button"
          aria-label={day_aria_label(day, @today, @selected_date, state == :open)}
          aria-pressed={if day == @selected_date, do: "true", else: "false"}
          aria-current={if day == @today, do: "date"}
          aria-disabled={if state != :open, do: "true"}
          class={cell_class(state, day == @selected_date, day == @today)}
        >
          <time datetime={Date.to_iso8601(day)} aria-hidden="true" class="relative z-10">
            {Localize.DateTime.to_string!(day, format: "d")}
          </time>
          <.key_date_icon date={day} selected?={day == @selected_date} muted?={state == :past} />
        </button>
      </:day>
      <:footer :let={month}><.key_date_caption month={month} /></:footer>
    </.live_component>
    """
  end

  defp cell_class(state, selected?, today?) do
    base = "relative aspect-square"

    state_class =
      cond do
        state != :open ->
          "cursor-not-allowed text-base-content/20"

        selected? ->
          "cursor-pointer bg-primary text-primary-content hover:bg-primary/90"

        true ->
          "cursor-pointer hover:bg-base-content/20"
      end

    if today?, do: "#{base} #{state_class} underline", else: "#{base} #{state_class}"
  end

  defp day_aria_label(day, today, selected_date, selectable?) do
    suffixes = [
      if(day == today, do: ~t"today"),
      if(day == selected_date, do: ~t"selected"),
      if(not selectable?, do: ~t"not available")
    ]

    Enum.join([Localize.Date.to_string!(day, format: :full) | Enum.reject(suffixes, &is_nil/1)], ", ")
  end

  # The value comes from the form's params, so it may not be a date at all.
  defp parse_date(%Date{} = date), do: date

  defp parse_date(value) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end
end
