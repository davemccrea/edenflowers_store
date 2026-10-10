defmodule EdenflowersWeb.KeyDateIcon do
  @moduledoc """
  Renders the florist-relevant key-date decoration, used in both the checkout
  calendar and the admin fulfillment calendar. Both calendars route through
  this component so the treatment can't drift between them.

  A cell gets a faint flower watermark behind its digit; the calendar's footer
  names the month's key dates, since the watermark alone can't say which day
  it is.
  """
  use EdenflowersWeb, :html

  alias Edenflowers.Fulfillment.KeyDates

  attr :date, Date, required: true

  attr :selected?, :boolean,
    default: false,
    doc: "The cell has the primary fill, so the mark flips to its content colour."

  attr :muted?, :boolean, default: false, doc: "Render at lower opacity (use on faded cells, e.g. past dates)."

  def key_date_icon(assigns) do
    ~H"""
    <span :if={KeyDates.key_date?(@date)} class="pointer-events-none absolute inset-1.5" aria-hidden="true">
      <.flower
        name="flower-30"
        class={["h-full w-full", if(@selected?, do: "text-primary-content/35", else: "text-primary/25"), @muted? && "opacity-50"]}
      />
    </span>
    """
  end

  attr :month, Date, required: true, doc: "Any date in the month to caption."

  def key_date_caption(assigns) do
    assigns = assign(assigns, :key_dates, KeyDates.for_month(assigns.month))

    ~H"""
    <ul :if={@key_dates != []} class="border-base-content/20 mt-2 space-y-1 border-t px-1 pt-2">
      <li :for={%{key: key, date: date} <- @key_dates} class="flex items-center gap-2">
        <.flower name="flower-30" class="text-primary/70 h-5 w-5 shrink-0" />
        <span class="font-serif text-base-content/85 italic">
          {Localize.DateTime.to_string!(date, format: "EEEE d MMMM")} · {label(key)}
        </span>
      </li>
    </ul>
    """
  end

  # Valentine's Day is Friend's Day (Ystävänpäivä / Vändagen) in Finland; the
  # fi and sv translations carry the local name.
  defp label(:valentines_day), do: ~t"Valentine's Day"
  defp label(:womens_day), do: ~t"Women's Day"
  defp label(:mothers_day), do: ~t"Mother's Day"
  defp label(:fathers_day), do: ~t"Father's Day"
end
