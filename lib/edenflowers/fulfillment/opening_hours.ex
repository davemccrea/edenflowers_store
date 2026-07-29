defmodule Edenflowers.Fulfillment.OpeningHours do
  use Ash.Resource, domain: Edenflowers.Fulfillment, data_layer: AshPostgres.DataLayer

  postgres do
    table "opening_hours"
    repo Edenflowers.Repo
  end

  attributes do
    uuid_primary_key :id
  end
end
