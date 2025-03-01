# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Edenflowers.Repo.insert!(%Edenflowers.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Edenflowers.Store.{TaxRate, FulfillmentOption}

tax_rate =
  TaxRate
  |> Ash.Changeset.for_create(:create, %{
    name: "Default",
    percentage: "0.255"
  })
  |> Ash.create!()

FulfillmentOption
|> Ash.Changeset.for_create(:create, %{
  name: "Home delivery",
  fulfillment_method: :delivery,
  rate_type: :dynamic,
  minimum_cart_total: 0,
  base_price: "3.00",
  price_per_km: "1.50",
  free_dist_km: 5,
  max_dist_km: 20,
  tax_rate_id: tax_rate.id
})
|> Ash.create!()

Ash.Changeset.for_create(FulfillmentOption, :create, %{
  name: "In store pickup",
  fulfillment_method: :pickup,
  rate_type: :fixed,
  base_price: "0.00",
  tax_rate_id: tax_rate.id
})
|> Ash.create!()
