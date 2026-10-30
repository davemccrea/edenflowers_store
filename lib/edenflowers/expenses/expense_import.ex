defmodule Edenflowers.Expenses.ExpenseImport do
  @moduledoc """
  Tracks one Papra document from webhook receipt, or upload from an invoice email, through extraction into an expense. Its Oban trigger retries processing and records terminal failures; a scheduled action imports the invoice emails.
  """

  use Ash.Resource,
    domain: Edenflowers.Expenses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias Edenflowers.Expenses.Changes

  postgres do
    table "expense_imports"
    repo Edenflowers.Repo

    # Removing the import with its expense lets the document be re-imported by tagging it again.
    references do
      reference :expense, on_delete: :delete
    end
  end

  oban do
    triggers do
      trigger :process do
        action :process
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Expenses.Workers.Process
        scheduler_module_name Edenflowers.Expenses.Schedulers.Process
        default_actor Edenflowers.Actors.system_actor()
        on_error :mark_failed
        where expr(is_nil(processed_at) and is_nil(failed_at))
      end
    end

    # Each run retries whatever the last one left in the folder, so a failed job isn't retried.
    scheduled_actions do
      schedule :import_invoice_emails, "*/15 * * * *" do
        action :import_invoice_emails
        queue :default
        worker_module_name Edenflowers.Expenses.Workers.ImportInvoiceEmails
        default_actor Edenflowers.Actors.system_actor()
      end
    end
  end

  actions do
    defaults [:read]

    create :record do
      description "Records a Papra document from its webhook and queues it for extraction into an expense. The same " <>
                    "document twice is recorded once."

      accept [:document_id, :organization_id]
      upsert? true
      upsert_identity :unique_document_id
      upsert_fields [:organization_id]
      change run_oban_trigger(:process)
    end

    action :import_invoice_emails do
      description "Uploads each PDF attached to the invoice emails in the Fastmail folder `Fakturor` to Papra, " <>
                    "records it for extraction and moves the email to `Fakturor/Importerade`. Emails without a " <>
                    "PDF stay put. Does nothing without a Fastmail API token, which only production has."

      run Edenflowers.Expenses.Actions.ImportInvoiceEmails
    end

    update :process do
      description "Fetches the document from Papra, has Claude extract an expense from it, and links the expense. " <>
                    "Run by the Oban trigger, which retries until it succeeds or calls `mark_failed`."

      accept []
      transaction? false
      require_atomic? false
      change Changes.Process
    end

    update :mark_failed do
      description "Stops the scheduler retrying a document that failed every attempt."
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
    belongs_to :expense, Edenflowers.Expenses.Expense do
      description "The expense extracted from the document. Nil until processed."
    end
  end

  identities do
    identity :unique_document_id, [:document_id]
  end
end
