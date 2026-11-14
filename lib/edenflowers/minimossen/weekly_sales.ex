defmodule Edenflowers.Minimossen.WeeklySales do
  @moduledoc """
  What one Winpos product group sold through Minimossen's till in one week, Monday
  to Sunday, as Stormossen's weekly report gives it. A scheduled action imports the
  reports from the shop's mailbox.
  """

  use Ash.Resource,
    domain: Edenflowers.Minimossen,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias Edenflowers.Minimossen.Actions

  attributes do
    uuid_primary_key :id

    attribute :week_start, :date do
      description "The Monday the week starts."
      allow_nil? false
    end

    attribute :group_code, :string do
      description "The Winpos product group's code: 3 is flowers; 6, 7 and 66 are the shop."
      allow_nil? false
    end

    attribute :group_name, :string do
      description "The product group's name in Winpos, e.g. `Eden Flowers kukat`."
      allow_nil? false
    end

    attribute :gross, :decimal do
      description "Sales including VAT (Myynti), before Stormossen's commission and card fees."
      allow_nil? false
      constraints scale: 2
    end

    timestamps()
  end

  identities do
    identity :unique_week_group, [:week_start, :group_code]
  end

  actions do
    defaults [:read]

    create :record do
      description "Records a product group's week from a Winpos report. The same week and group again " <>
                    "overwrites it, so importing a report twice changes nothing."

      accept [:week_start, :group_code, :group_name, :gross]
      upsert? true
      upsert_identity :unique_week_group
      upsert_fields [:group_name, :gross]
    end

    action :import_reports do
      description "Records the weekly sales in each Winpos report attached to the emails in the Fastmail folder " <>
                    "`Winpos` and moves the email to `Winpos/Importerade`. Emails without a report stay put. " <>
                    "Does nothing without a Fastmail API token, which only production has."

      run Actions.ImportReports
    end

    action :recent_sales, :map do
      description "The product groups sold in those periods, sorted by code; each group's gross sales and the " <>
                    "total for each of the last `count` weeks, months or years up to the latest week imported, " <>
                    "oldest first, from the first with a report, where one without a report reads 0. A week " <>
                    "counts in the month and year its Thursday falls in. By week, also the average of the 8 " <>
                    "weeks before the latest, leaving out weeks without a report. And the total for the latest " <>
                    "week's year, from the first week imported in it. No periods or year before any import, and " <>
                    "no average by month or year, or without an earlier report."

      constraints fields: [
                    groups: [type: {:array, :map}, allow_nil?: false],
                    periods: [type: {:array, :map}, allow_nil?: false],
                    average: [type: :map, allow_nil?: true],
                    year: [type: :map, allow_nil?: true]
                  ]

      argument :period, :atom, default: :week, constraints: [one_of: [:week, :month, :year]]
      argument :count, :integer, default: 12, constraints: [min: 1]
      run Actions.RecentSales
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    policy action([:read, :recent_sales]) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  oban do
    # Each run retries whatever the last one left in the folder, so a failed job isn't retried.
    scheduled_actions do
      schedule :import_reports, "0 * * * *" do
        action :import_reports
        queue :default
        worker_module_name Edenflowers.Minimossen.Workers.ImportReports
        default_actor Edenflowers.Actors.system_actor()
      end
    end
  end

  postgres do
    table "minimossen_weekly_sales"
    repo Edenflowers.Repo

    # The generator would carry `scale: 2` into the migration, which Ecto rejects without a precision.
    migration_types gross: :decimal
  end
end
