defmodule Edenflowers.Bank.Connection do
  @moduledoc """
  A consent Jennie gave, by logging in to S-Pankki, for the shop to read the
  accounts she picked. It lasts as long as the bank allows (180 days), then
  she connects again. Each connection is a new row; the newest is current.
  """

  use Ash.Resource,
    domain: Edenflowers.Bank,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshOban]

  alias Edenflowers.External.EnableBankingAPI

  postgres do
    table "bank_connections"
    repo Edenflowers.Repo
  end

  # Four runs a day, the most PSD2 allows without Jennie at the bank.
  oban do
    scheduled_actions do
      schedule :sync_payments, "0 */6 * * *" do
        action :sync_payments
        queue :default
        worker_module_name Edenflowers.Bank.Workers.SyncPayments
        default_actor Edenflowers.Actors.system_actor()
      end
    end
  end

  actions do
    defaults [:read]

    action :sync_payments do
      description "Reads the shop's booked bank transactions, marks paid the expenses they pay and records " <>
                    "the invoice payments they bring. " <>
                    "Does nothing without Enable Banking configured, which only production is, " <>
                    "or without a current consent."

      run Edenflowers.Bank.Actions.SyncPayments
    end

    read :current do
      description "The newest connection, expired or not; nil before the bank was ever connected."
      get? true
      prepare build(sort: [inserted_at: :desc], limit: 1)
    end

    action :authorization_url, :string do
      description "Starts a consent at Enable Banking and returns the S-Pankki login Jennie is sent to. " <>
                    "The bank sends her back to `redirect_url` with `state` and a one-time code for `connect`."

      argument :state, :string, allow_nil?: false
      argument :redirect_url, :string, allow_nil?: false

      run fn input, _context ->
        EnableBankingAPI.start_authorization(input.arguments.state, input.arguments.redirect_url)
      end
    end

    create :connect do
      description "Swaps the one-time code from the bank's redirect for a session on the accounts Jennie approved."

      argument :code, :string, allow_nil?: false

      change before_action(fn changeset, _context ->
               case EnableBankingAPI.create_session(Ash.Changeset.get_argument(changeset, :code)) do
                 {:ok, session} ->
                   Ash.Changeset.force_change_attributes(changeset, session)

                 {:error, reason} ->
                   Ash.Changeset.add_error(changeset, "The bank didn't accept the login: #{inspect(reason)}")
               end
             end)
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action_type(:read)
      authorize_if action(:sync_payments)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :session_id, :string do
      description "Enable Banking's session, which every account read names."
      allow_nil? false
    end

    attribute :account_ids, {:array, :string} do
      description "Enable Banking's ids for the accounts Jennie approved."
      allow_nil? false
    end

    attribute :valid_until, :utc_datetime do
      description "When the bank's consent ends and Jennie has to connect again."
      allow_nil? false
    end

    create_timestamp :inserted_at
  end

  calculations do
    calculate :expired, :boolean, expr(valid_until <= now()) do
      description "The consent has ended, so nothing is read until Jennie connects again."
    end

    calculate :renewal_due, :boolean, expr(valid_until <= datetime_add(now(), 14, :day)) do
      description "Ends within two weeks or already has: time to ask Jennie to connect again."
    end
  end
end
