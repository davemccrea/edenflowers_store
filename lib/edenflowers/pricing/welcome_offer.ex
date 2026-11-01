defmodule Edenflowers.Pricing.WelcomeOffer do
  @moduledoc """
  The discount a new newsletter subscriber's welcome code is generated with.
  Jennie changes it for limited-time offers and changes it back herself.

  There is one row. `:get` creates it on first use at 15%, so a fresh
  database needs no seed. Each code copies the rate when it's generated, so
  codes already sent keep theirs.
  """
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "welcome_offer"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read]

    action :get, :struct do
      description "The welcome offer, created on first use at 15%."
      constraints instance_of: __MODULE__

      run fn _input, context ->
        opts = Ash.Context.to_opts(context)

        case Ash.read_one(__MODULE__, opts) do
          {:ok, nil} -> Ash.create(__MODULE__, %{}, Keyword.put(opts, :action, :create))
          result -> result
        end
      end
    end

    create :create do
      description "Creates the one welcome offer row, or returns the existing one. Called by `get` on first use."
      upsert? true
      upsert_identity :singleton
      upsert_fields [:singleton]
    end

    update :update do
      description "Sets the discount new subscribers' welcome codes are generated with. Codes already sent keep " <>
                    "their rate."

      accept [:discount_rate]
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # The footer and checkout show the percent to everyone, and signup reads it to generate a code.
    policy action([:read, :get, :create]) do
      authorize_if always()
    end

    policy action_type(:update) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :singleton, :boolean do
      description "Always true, so the unique identity on it allows one row."
      allow_nil? false
      default true
      writable? false
    end

    attribute :discount_rate, :decimal do
      description "The welcome discount as a fraction, so 0.15 is 15% off."
      allow_nil? false
      default Decimal.new("0.15")
      constraints greater_than: 0, max: 1
      public? true
    end
  end

  identities do
    identity :singleton, [:singleton]
  end
end
