defmodule Edenflowers.Repo.Migrations.CreateDrivers do
  @moduledoc """
  Creates the drivers table for the Edenflowers.Delivery domain.
  """

  use Ecto.Migration

  def up do
    create table(:drivers, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :phone, :text
      add :email, :text
      add :locale, :text, null: false, default: "en-GB"
      add :active?, :boolean, null: false, default: true
      add :link_token, :text, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:drivers, [:link_token], name: "drivers_unique_link_token_index")
  end

  def down do
    drop_if_exists unique_index(:drivers, [:link_token], name: "drivers_unique_link_token_index")

    drop table(:drivers)
  end
end
