defmodule Edenflowers.Repo.Migrations.Order do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    alter table(:orders) do
      add :calculated_address, :text
      add :position, :text
    end
  end

  def down do
    alter table(:orders) do
      remove :position
      remove :calculated_address
    end
  end
end
