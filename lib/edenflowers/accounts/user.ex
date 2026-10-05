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
      token_lifetime {30, :days}
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      otp do
        identity_field :email
        registration_enabled? true
        brute_force_strategy :rate_limit
        otp_characters :digits_only

        sender Edenflowers.Accounts.Senders.SendOtp
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

    update :update_avatar do
      accept [:avatar, :avatar_content_type]
    end

    update :remove_avatar do
      change set_attribute(:avatar, nil)
      change set_attribute(:avatar_content_type, nil)
    end

    # Table feed for /admin/customers. A customer is anyone with a placed order;
    # users who only signed in or subscribed to the newsletter are left out.
    read :admin_list do
      pagination offset?: true, keyset?: true, countable: true, required?: false

      filter expr(exists(placed_orders, true))

      prepare build(
                sort: [last_ordered_at: :desc],
                load: [:placed_order_count, :last_ordered_at, :total_spent]
              )
    end

    read :admin_show do
      filter expr(exists(placed_orders, true))

      prepare build(load: [:placed_order_count, :last_ordered_at, :total_spent])
    end

    update :set_newsletter_promo do
      accept [:newsletter_promo_id]
      require_attributes [:newsletter_promo_id]
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

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: true, public?: true
    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :newsletter_opt_in, :boolean, allow_nil?: false, default: false, public?: true

    attribute :admin, :boolean, default: false, public?: true, writable?: false

    attribute :avatar, :binary, allow_nil?: true, select_by_default?: false
    attribute :avatar_content_type, :string, allow_nil?: true
  end

  relationships do
    belongs_to :newsletter_promo, Edenflowers.Pricing.Promotion

    has_many :placed_orders, Edenflowers.Orders.Order do
      filter expr(state == :placed)
      sort ordered_at: :desc
    end
  end

  calculations do
    calculate :first_name, :string, {Edenflowers.Accounts.Calculations.FirstName, source: :name}
    calculate :initials, :string, {Edenflowers.Accounts.Calculations.Initials, source: :name}
    # A user without a promo has no usage, so the `if` turns that NULL into a strict false.
    calculate :newsletter_offer_hidden?,
              :boolean,
              expr(if(newsletter_opt_in or newsletter_promo.usage > 0, true, false))
  end

  aggregates do
    count :placed_order_count, :placed_orders
    max :last_ordered_at, :placed_orders, :ordered_at

    # Money received, so only paid orders count (see ADR 0001). `amount_paid` is
    # what Stripe actually charged, which can differ from the order's total.
    sum :total_spent, :placed_orders, :amount_paid do
      filter expr(payment_status == :paid)
      default Decimal.new("0")
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
