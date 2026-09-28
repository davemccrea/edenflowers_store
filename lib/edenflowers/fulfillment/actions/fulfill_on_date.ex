defmodule Edenflowers.Fulfillment.Actions.FulfillOnDate do
  use Ash.Resource.Actions.Implementation

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability

  @impl true
  def run(input, _opts, _context) do
    %{fulfillment_option_id: option_id, date: date, now: now} = input.arguments

    with {:ok, option} <- Fulfillment.get_option_by_id(option_id, authorize?: false) do
      # `unavailable_reason/3` compares against the same-day deadline in Helsinki time.
      {:ok, Availability.unavailable_reason(option, date, DateTime.shift_zone!(now, "Europe/Helsinki"))}
    end
  end
end
