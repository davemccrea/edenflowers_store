defmodule Edenflowers.Accounts.User do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshRateLimiter, AshAdmin.Resource]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Edenflowers.Accounts.Token
      signing_secret Edenflowers.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      otp do
        identity_field :email
        registration_enabled? true
        brute_force_strategy :rate_limit

        sender Edenflowers.Accounts.User.Senders.SendOtp
      end

      google do
        client_id Edenflowers.Secrets
        client_secret Edenflowers.Secrets
        redirect_uri Edenflowers.Secrets
        identity_resource Edenflowers.Accounts.UserIdentity
        prevent_hijacking? false
      end
    end
  end

  postgres do
    table "users"
    repo Edenflowers.Repo
  end

  rate_limit do
    backend Edenflowers.RateLimiter

    action :request_otp,
      limit: 5,
      per: :timer.minutes(15),
      key: fn input -> "otp:request:#{input.arguments[:email]}" end

    action :sign_in_with_otp,
      limit: 5,
      per: :timer.minutes(10),
      key: fn input -> "otp:sign_in:#{input.arguments[:email]}" end
  end

  admin do
    actor?(true)
  end

  code_interface do
    define :get_by_subject, action: :get_by_subject, args: [:subject]
    define :get_by_email, action: :get_by_email, args: [:email]
    define :upsert, action: :upsert, args: [:email, :name]
    define :request_otp, action: :request_otp, args: [:email]
    define :sign_in_with_otp, action: :sign_in_with_otp, args: [:email, :otp]
    define :subscribe_to_newsletter, action: :subscribe_to_newsletter, args: [:email]
    define :update_name, action: :update_name, args: [:name]
    define :update_newsletter_preference, action: :update_newsletter_preference, args: [:newsletter_opt_in]
    define :set_newsletter_promo, action: :set_newsletter_promo, args: [:newsletter_promo_id]
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get? true

      argument :email, :ci_string, allow_nil?: false

      filter expr(email == ^arg(:email))
    end

    create :upsert do
      accept [:email, :name]
      upsert? true
      upsert_identity :unique_email
    end

    update :update do
      accept [:name, :newsletter_opt_in]
    end

    create :subscribe_to_newsletter do
      accept [:email]
      upsert? true
      upsert_identity :unique_email
      change set_attribute(:newsletter_opt_in, true)
    end

    update :update_name do
      accept [:name]
    end

    update :update_newsletter_preference do
      accept [:newsletter_opt_in]
    end

    update :set_newsletter_promo do
      argument :newsletter_promo_id, :uuid, allow_nil?: false
      change set_attribute(:newsletter_promo_id, arg(:newsletter_promo_id))
    end

    create :register_with_google do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      upsert? true
      upsert_identity :unique_email

      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.OAuth2.IdentityChange

      change fn changeset, _ctx ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        changeset
        |> Ash.Changeset.change_attribute(:email, user_info["email"])
        |> Ash.Changeset.change_attribute(:name, user_info["name"])
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action_type(:update) do
      authorize_if expr(id == ^actor(:id))
    end

    # Anyone can subscribe to the newsletter (no actor required).
    policy action(:subscribe_to_newsletter) do
      authorize_if always()
    end
  end

  preparations do
    prepare build(load: [:newsletter_subscribed?, :newsletter_promo_used?])
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: true, public?: true
    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :newsletter_opt_in, :boolean, default: false, public?: true

    attribute :admin, :boolean, default: false, public?: true, writable?: false
  end

  relationships do
    belongs_to :newsletter_promo, Edenflowers.Pricing.Promotion
  end

  calculations do
    calculate :first_name, :string, {Edenflowers.Accounts.Calculations.FirstName, source: :name}
    calculate :newsletter_subscribed?, :boolean, expr(newsletter_opt_in == true)
    calculate :newsletter_promo_used?, :boolean, expr(newsletter_promo.usage > 0)
  end

  identities do
    identity :unique_email, [:email]
  end
end
