defmodule Edenflowers.Repo.Migrations.RenameCategoryDraftToVisibility do
  @moduledoc """
  Replaces ProductCategory.draft (boolean) with .visibility (:public | :draft
  | :hidden). The boolean conflated "work-in-progress" with "deliberately
  hidden from storefront" — splitting them lets categories like Cards exist
  as data (surfaced at checkout) without appearing in the public ribbon.

  Backfill maps the existing boolean:
    draft = true  -> :draft   (still being prepared)
    draft = false -> :public  (live in the store)

  Categories that should become :hidden (e.g. Cards) must be flipped by hand
  after this migration runs, or via reseeding.
  """

  use Ecto.Migration

  def up do
    alter table(:product_categories) do
      add :visibility, :text
    end

    execute("""
    UPDATE product_categories
    SET visibility = CASE WHEN draft THEN 'draft' ELSE 'public' END
    """)

    alter table(:product_categories) do
      modify :visibility, :text, null: false, default: "draft"
      remove :draft
    end
  end

  def down do
    alter table(:product_categories) do
      add :draft, :boolean
    end

    execute("""
    UPDATE product_categories
    SET draft = CASE WHEN visibility = 'public' THEN false ELSE true END
    """)

    alter table(:product_categories) do
      modify :draft, :boolean, null: false, default: true
      remove :visibility
    end
  end
end
