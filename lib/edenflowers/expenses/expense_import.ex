defmodule Edenflowers.Expenses.ExpenseImport do
  use Ash.Resource,
    domain: Edenflowers.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  postgres do
    table "expense_imports"
    repo Edenflowers.Repo
  end

  oban do
    triggers do
      trigger :process do
        action :process
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Expenses.ExpenseImport.Workers.Process
        scheduler_module_name Edenflowers.Expenses.ExpenseImport.Schedulers.Process
        default_actor Edenflowers.Actors.system_actor()
        on_error :mark_failed
        where expr(is_nil(processed_at) and is_nil(failed_at))
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:document_id, :organization_id]
      upsert? true
      upsert_identity :unique_document_id
      upsert_fields [:organization_id]
      change run_oban_trigger(:process)
    end

    update :process do
      accept []
      transaction? false
      require_atomic? false
      change Edenflowers.Expenses.ExpenseImport.Changes.Process
    end

    # Stops the scheduler retrying a document that failed every attempt.
    update :mark_failed do
      accept []
      change set_attribute(:failed_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type(:read)
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :document_id, :string, allow_nil?: false
    attribute :organization_id, :string, allow_nil?: false
    attribute :processed_at, :utc_datetime
    attribute :failed_at, :utc_datetime
    timestamps()
  end

  relationships do
    belongs_to :expense, Edenflowers.Expenses.Expense
  end

  identities do
    identity :unique_document_id, [:document_id]
  end
end
