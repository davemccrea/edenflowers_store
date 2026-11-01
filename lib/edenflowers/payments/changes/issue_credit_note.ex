defmodule Edenflowers.Payments.Changes.IssueCreditNote do
  @moduledoc """
  Dates a new credit note today in Helsinki and gives it the next number in
  the series it shares with Invoices (`NumberSeries`), taken just before the
  insert.
  """
  use Ash.Resource.Change

  alias Edenflowers.Payments.NumberSeries
  alias Edenflowers.ShopTime

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(:credit_date, ShopTime.today())
    |> Ash.Changeset.before_action(&Ash.Changeset.force_change_attribute(&1, :number, NumberSeries.take()))
  end
end
