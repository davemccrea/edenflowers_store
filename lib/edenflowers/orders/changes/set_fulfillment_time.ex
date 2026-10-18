defmodule Edenflowers.Orders.Changes.SetFulfillmentTime do
  @moduledoc """
  Sets a Custom Order's time from Jennie's choice of any time, an exact time
  or a window, so neither time field means something by being blank.
  Without a choice the times are left as they are.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :fulfillment_time) do
      nil ->
        changeset

      :any ->
        Ash.Changeset.force_change_attributes(changeset, fulfillment_time_start: nil, fulfillment_time_end: nil)

      :at ->
        changeset
        |> Ash.Changeset.force_change_attribute(:fulfillment_time_end, nil)
        |> require_time(:fulfillment_time_start)

      :between ->
        changeset
        |> require_time(:fulfillment_time_start)
        |> require_time(:fulfillment_time_end)
        |> require_end_after_start()
    end
  end

  defp require_time(changeset, field) do
    if Ash.Changeset.get_attribute(changeset, field),
      do: changeset,
      else: Ash.Changeset.add_error(changeset, field: field, message: ~t"Enter a time")
  end

  defp require_end_after_start(changeset) do
    start = Ash.Changeset.get_attribute(changeset, :fulfillment_time_start)
    finish = Ash.Changeset.get_attribute(changeset, :fulfillment_time_end)

    if start && finish && Time.compare(finish, start) != :gt,
      do: Ash.Changeset.add_error(changeset, field: :fulfillment_time_end, message: ~t"Must be after the start"),
      else: changeset
  end
end
