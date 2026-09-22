defmodule Edenflowers.Orders.VatRow do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :rate, :decimal, allow_nil?: false, public?: true
    attribute :base, :decimal, allow_nil?: false, public?: true
    attribute :vat, :decimal, allow_nil?: false, public?: true
    attribute :gross, :decimal, allow_nil?: false, public?: true
  end
end
