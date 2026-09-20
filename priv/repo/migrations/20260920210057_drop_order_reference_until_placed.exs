defmodule Edenflowers.Repo.Migrations.DropOrderReferenceUntilPlaced do
  @moduledoc """
  Lets `order_reference` be null until an order is actually placed.

  `InitStore` creates a cart row for every browser session, so minting the
  reference at creation spent the keyspace on visitors and bots rather than on
  orders. Generation moved to `finalize_checkout`; a cart now carries no
  reference at all.

  The unique index stays as it is — Postgres counts nulls as distinct, so any
  number of carts can sit at null while placed orders stay unique.

  `down` restores NOT NULL, so it only succeeds once no null references are
  left — clear out the open carts first.
  """
  use Ecto.Migration

  def up do
    alter table(:orders) do
      modify :order_reference, :text, null: true
    end
  end

  def down do
    alter table(:orders) do
      modify :order_reference, :text, null: false
    end
  end
end
