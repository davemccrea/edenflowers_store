defmodule Edenflowers.Accounts.User do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

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
      magic_link do
        identity_field :email
        registration_enabled? true
        require_interaction? true

        sender Edenflowers.Accounts.User.Senders.SendMagicLinkEmail
      end
    end
  end

  postgres do
    table "users"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_subject, action: :get_by_subject, args: [:subject]
    define :get_by_email, action: :get_by_email, args: [:email]
    define :upsert, action: :upsert, args: [:email, :name]
    define :sign_in_with_magic_link, action: :sign_in_with_magic_link, args: [:token]
    define :request_magic_link, action: :request_magic_link, args: [:email]
    define :subscribe_to_newsletter, action: :subscribe_to_newsletter, args: [:email]
    define :update_name, action: :update_name, args: [:name]
    define :update_newsletter_preference, action: :update_newsletter_preference, args: [:newsletter_opt_in]
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

      argument :email, :ci_string do
        allow_nil? false
      end

      filter expr(email == ^arg(:email))
    end

    create :upsert do
      accept [:email, :name]
      upsert? true
      upsert_identity :unique_email
    end

    update :update do
      description "Users can update their own safe fields (admin is NOT writable)"
      # Explicitly exclude admin field - it's already writable?: false but this is defense in depth
      accept [:name, :newsletter_opt_in]
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
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
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Users can read their own data
    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
    end

    # Users can update their own data
    policy action_type(:update) do
      authorize_if expr(id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: true, public?: true
    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :newsletter_opt_in, :boolean, default: false, public?: true

    # Admin field - readable but not writable to prevent privilege escalation
    attribute :admin, :boolean, default: false, public?: true, writable?: false
  end

  identities do
    identity :unique_email, [:email]
  end
end
