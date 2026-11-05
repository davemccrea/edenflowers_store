defmodule Edenflowers.Payments.GiftVoucher.LaterLastDay do
  @moduledoc """
  Refuses a new last day unless `last_day_changeable?` holds and the date is
  later than the current one: a voucher's time is only ever given, not taken.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    # Read afresh, so a page showing an older last day can't move it earlier.
    voucher = Ash.get!(changeset.resource, changeset.data.id, load: [:last_day_changeable?], authorize?: false)
    new_date = Ash.Changeset.get_attribute(changeset, :expires_on)

    cond do
      not voucher.last_day_changeable? ->
        {:error, field: :expires_on, message: "can't change on a cancelled or used-up voucher"}

      Date.compare(new_date, voucher.expires_on) != :gt ->
        {:error, field: :expires_on, message: "must be later than the current last day"}

      true ->
        :ok
    end
  end
end
