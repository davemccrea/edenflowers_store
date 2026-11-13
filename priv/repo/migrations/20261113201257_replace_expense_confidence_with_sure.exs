defmodule Edenflowers.Repo.Migrations.ReplaceExpenseConfidenceWithSure do
  @moduledoc """
  Replaces Claude's high/medium/low confidence with a sure/unsure flag, since
  only "not high" ever mattered: it asks for Jennie's review.
  """

  use Ecto.Migration

  def up do
    alter table(:expenses) do
      add :sure, :boolean
    end

    execute "UPDATE expenses SET sure = (confidence = 'high')"

    alter table(:expenses) do
      modify :sure, :boolean, null: false
      remove :confidence
    end
  end

  def down do
    alter table(:expenses) do
      add :confidence, :text
    end

    execute "UPDATE expenses SET confidence = CASE WHEN sure THEN 'high' ELSE 'medium' END"

    alter table(:expenses) do
      modify :confidence, :text, null: false
      remove :sure
    end
  end
end
