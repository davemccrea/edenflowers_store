defmodule Edenflowers.Courses.Changes.SendCancelledEmail do
  @moduledoc """
  Queues the email telling the customer their booking is cancelled and what
  was refunded, in the cancel's own transaction, so it never goes out for a
  cancel that rolled back.

  A hold released before the customer paid was never a booking, so nobody
  is told.
  """
  use Ash.Resource.Change

  alias Edenflowers.Courses.Workers.SendCancelledEmail

  @impl true
  def change(%{data: %{status: :confirmed}} = changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(:cancellation_emailed_to, changeset.data.email)
    |> Ash.Changeset.after_action(fn changeset, registration ->
      with {:ok, _job} <- registration |> SendCancelledEmail.new_for(changeset.context) |> Oban.insert() do
        {:ok, registration}
      end
    end)
  end

  def change(changeset, _opts, _context), do: changeset
end
