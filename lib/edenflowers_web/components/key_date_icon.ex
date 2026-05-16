defmodule EdenflowersWeb.KeyDateIcon do
  @moduledoc """
  Renders the florist-relevant key-date marker for a single date, used as a
  decoration in both the checkout calendar and the admin fulfillment
  calendar. Both calendars route through this component so the marker's
  visual treatment can't drift between them.
  """
  use EdenflowersWeb, :html

  alias Edenflowers.Store.KeyDates

  attr :date, Date, required: true
  attr :muted?, :boolean, default: false, doc: "Render at lower opacity (use on faded cells, e.g. past dates)."

  def key_date_icon(assigns) do
    assigns = assign(assigns, :decoration, KeyDates.lookup_for(assigns.date))

    ~H"""
    <.icon
      :if={@decoration}
      name={@decoration.icon}
      class={["pointer-events-none absolute inset-0 m-auto h-9 w-9", @decoration.colour_class, @muted? && "opacity-50"]}
    />
    """
  end
end
