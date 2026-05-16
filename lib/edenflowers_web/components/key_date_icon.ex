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

  def key_date_icon(assigns) do
    ~H"""
    <.icon
      :if={icon = KeyDates.icon_for(@date)}
      name={icon}
      class="text-error absolute top-0.5 left-0.5 h-2.5 w-2.5"
    />
    """
  end
end
