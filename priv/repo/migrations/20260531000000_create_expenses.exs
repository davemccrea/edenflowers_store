defmodule Edenflowers.Repo.Migrations.CreateExpenses do
  @moduledoc """
  Creates the expenses table for the Edenflowers.Expenses domain.
  """

  use Ecto.Migration

  def up do
    create table(:expenses, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :document_id, :text, null: false
      add :vendor_name, :text
      add :vendor_vat_number, :text
      add :date, :date
      add :total_amount, :decimal
      add :vat_amount, :decimal
      add :currency, :text
      add :category, :text
      add :description, :text
      add :confidence, :text, null: false
      add :processed_at, :utc_datetime, null: false
      add :reviewed_at, :utc_datetime
      add :inserted_at, :utc_datetime, null: false
      add :updated_at, :utc_datetime, null: false
    end

    create unique_index(:expenses, [:document_id])
  end

  def down do
    drop table(:expenses)
  end
end
