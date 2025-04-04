defmodule Edenflowers.Repo.Migrations.ModifyLineItem do
  @moduledoc """
  Updates resources based on their most recent snapshots.

  This file was autogenerated with `mix ash_postgres.generate_migrations`
  """

  use Ecto.Migration

  def up do
    rename table(:line_items), :product_image_url, to: :product_image_slug
  end

  def down do
    rename table(:line_items), :product_image_slug, to: :product_image_url
  end
end
