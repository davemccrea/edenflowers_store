defmodule Edenflowers.Pricing.Promotion.Changes.SetNewsletterDefaults do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    Ash.Changeset.force_change_attributes(changeset,
      code: Edenflowers.Pricing.Promotion.generate_code(),
      name: "Newsletter Welcome",
      discount_rate: Decimal.new("0.15"),
      minimum_cart_total: Decimal.new("0"),
      start_date: today,
      expiration_date: Date.add(today, 30),
      usage_limit: 1
    )
  end
end
