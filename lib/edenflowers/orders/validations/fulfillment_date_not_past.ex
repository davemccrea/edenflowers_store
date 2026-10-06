defmodule Edenflowers.Orders.Validations.FulfillmentDateNotPast do
  @moduledoc """
  The one date rule Jennie can't override on an order she enters herself: closed
  days and deadlines only warn her, but a date in the past is always a mistake.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :fulfillment_date) do
      %Date{} = date ->
        if Date.before?(date, today()) do
          {:error, field: :fulfillment_date, message: ~t"Fulfillment date cannot be in the past"}
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp today, do: DateTime.now!("Europe/Helsinki") |> DateTime.to_date()
end
