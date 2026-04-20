defmodule Edenflowers.Store.Promotion.Changes.SetNewsletterDefaults do
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    code = :crypto.strong_rand_bytes(3) |> Base.encode16()
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    changeset
    |> Ash.Changeset.force_change_attribute(:code, code)
    |> Ash.Changeset.force_change_attribute(:name, "Newsletter Welcome")
    |> Ash.Changeset.force_change_attribute(:discount_percentage, Decimal.new("0.15"))
    |> Ash.Changeset.force_change_attribute(:minimum_cart_total, Decimal.new("0"))
    |> Ash.Changeset.force_change_attribute(:start_date, today)
    |> Ash.Changeset.force_change_attribute(:expiration_date, Date.add(today, 30))
    |> Ash.Changeset.force_change_attribute(:usage_limit, 1)
  end
end
