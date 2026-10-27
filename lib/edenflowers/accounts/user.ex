defmodule Edenflowers.Accounts.User do
  @moduledoc """
  Customer and admin identity. Email one-time codes authenticate users; the same record links orders, course bookings, and newsletter preferences.
  """

  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshRateLimiter, AshAdmin.Resource]

  alias Edenflowers.Accounts.Calculations
  alias Edenflowers.Accounts.Changes
  alias Edenflowers.Pricing.Workers.SendNewsletterPromoEmail
  alias Edenflowers.Types.Email

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

    # Each code goes to an address the customer only claims to own.
    action :request_email_change, limit: 5, per: :timer.minutes(15)

    # Wrong codes are counted here rather than on the user: a failed confirm
    # rolls back anything it writes. Counted before the transaction so a wrong
    # code still counts.
    action :confirm_email_change, limit: 5, per: :timer.minutes(10), on: :before_transaction
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
      description "Finds or creates the user for a customer's email as a checkout, order or booking takes it, " <>
                    "setting their name."

      accept [:email, :name]
      upsert? true
      upsert_identity :unique_email
    end

    update :update do
      description "Changes a user's name, or their newsletter opt-in with the language it applies to. The " <>
                    "newsletter sync also uses it to opt out anyone who unsubscribed in Brevo."

      accept [:name, :newsletter_opt_in, :locale]
    end

    update :request_email_change do
      description "Holds the new address as pending and emails it a code. The email only changes once that code " <>
                    "comes back through `confirm_email_change`."

      require_atomic? false
      argument :email, Email, allow_nil?: false
      change Changes.RequestEmailChange
    end

    update :confirm_email_change do
      description "Moves the pending address into `email` when given the code sent to it, then clears the pending " <>
                    "change. Fails on a wrong or expired code; wrong guesses are rate limited."

      require_atomic? false
      argument :code, :string, allow_nil?: false, sensitive?: true
      # The pending change is read from the database, never from the caller's record.
      change get_and_lock_for_update()
      change Changes.ConfirmEmailChange
    end

    create :subscribe_to_newsletter do
      description "Opts an email in to the newsletter, creating the user if needed, and queues its welcome email. " <>
                    "A subscriber who already has a code is emailed the already-subscribed wording instead."

      accept [:email, :locale]
      upsert? true
      upsert_identity :unique_email
      change set_attribute(:newsletter_opt_in, true)

      # The welcome/promotion job is inserted in the same transaction, so an
      # opt-in never commits without its email queued. Returning subscribers
      # get it too; the worker sends them the "already subscribed" wording.
      change after_action(fn _changeset, user, _context ->
               with {:ok, _job} <-
                      SendNewsletterPromoEmail.enqueue(%{"email" => to_string(user.email), "locale" => user.locale}),
                    do: {:ok, user}
             end)
    end

    update :update_avatar do
      description "Stores an uploaded photo for the admin's account page and back office, in the database itself."
      accept [:avatar, :avatar_content_type]
    end

    update :remove_avatar do
      description "Removes the admin's photo, so the back office falls back to their initials."
      change set_attribute(:avatar, nil)
      change set_attribute(:avatar_content_type, nil)
    end

    read :admin_list do
      description "Table feed for /admin/customers, latest order first. A customer is anyone with a placed order; " <>
                    "users who only signed in or subscribed to the newsletter are left out."

      pagination offset?: true, keyset?: true, countable: true, required?: false

      filter expr(exists(placed_orders, true))

      prepare build(
                sort: [last_ordered_at: :desc],
                load: [:placed_order_count, :last_ordered_at, :total_spent]
              )
    end

    read :search do
      description "Admin search for customers by name or email, latest order first. Users without a placed order " <>
                    "are left out."

      argument :term, :ci_string, allow_nil?: false
      filter expr(exists(placed_orders, true) and (contains(name, ^arg(:term)) or contains(email, ^arg(:term))))
      prepare build(sort: [last_ordered_at: :desc])
    end

    read :admin_show do
      description "A customer for the admin, with their order count, last order date and total spent. Users without " <>
                    "a placed order are not found."

      filter expr(exists(placed_orders, true))

      prepare build(load: [:placed_order_count, :last_ordered_at, :total_spent])
    end

    update :ensure_stripe_customer do
      description "Creates a Stripe Customer for the user unless they already have one. Signed-in customers save " <>
                    "cards to it at checkout."

      require_atomic? false
      change get_and_lock_for_update()
      change Changes.CreateStripeCustomer
    end

    update :forget_stripe_customer do
      description "Drops a Stripe Customer that was deleted in Stripe, so the next checkout creates a new one."
      change set_attribute(:stripe_customer_id, nil)
    end

    read :brevo_contacts do
      description "Everyone the newsletter sync sends to Brevo: newsletter subscribers only, so customers who never " <>
                    "opted in have no profile there (privacy policy)."

      filter expr(newsletter_opt_in)
      prepare build(load: [:first_name, :last_name, :phone_number, :placed_order_count, :last_ordered_at, :total_spent])
    end

    update :set_newsletter_promo do
      description "Links the welcome promotion created for a newsletter subscriber, which hides the newsletter " <>
                    "offer once it's used."

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

    policy action(:subscribe_to_newsletter) do
      authorize_if always()
    end
  end

  validations do
    # email stays a :ci_string for case-insensitive matching, so the format
    # check from Edenflowers.Types.Email is applied here instead.
    validate match(:email, Email.format()),
      message: "Must be a valid email address",
      where: changing(:email)

    # A code can only reach a real address, so the sign-in page asks again
    # instead of waiting on one that never comes.
    validate match(:email, Email.format()),
      message: "Must be a valid email address",
      on: [:action],
      where: action_is(:request_otp)

    validate attribute_in(:locale, Edenflowers.Locales.all()), where: present(:locale)
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      description "Full name as one free-text field, as typed at checkout. Nil for someone who only signed in " <>
                    "or subscribed to the newsletter."

      allow_nil? true
      public? true
    end

    attribute :email, :ci_string do
      description "Sign-in identity, matched case-insensitively. Orders and course bookings for this address link here."
      allow_nil? false
      public? true
    end

    attribute :newsletter_opt_in, :boolean do
      description "Whether they get the newsletter, which is sent from Brevo."
      allow_nil? false
      default false
      public? true
    end

    attribute :locale, :string do
      description "The language they last opted in to the newsletter in, so campaigns can be split by language. " <>
                    "Nil for users who opted in before this was kept."

      allow_nil? true
      public? true
    end

    attribute :admin, :boolean do
      description "Gives back office access and bypasses every policy. No action can set it, so it is set in the database."
      default false
      public? true
      writable? false
    end

    attribute :reviewer, :boolean do
      description "Lets them leave review notes on any element of the site with Option+Click, without back " <>
                    "office access. No action can set it, so it is set in the database."

      default false
      public? true
      writable? false
    end

    attribute :avatar, :binary, allow_nil?: true, select_by_default?: false
    attribute :avatar_content_type, :string, allow_nil?: true

    attribute :stripe_customer_id, :string, allow_nil?: true

    attribute :pending_email, :ci_string do
      description "An email change waiting for its code. See `request_email_change`."
      allow_nil? true
    end

    attribute :pending_email_code_hash, :string, allow_nil?: true, sensitive?: true
    attribute :pending_email_expires_at, :utc_datetime_usec, allow_nil?: true
  end

  relationships do
    belongs_to :newsletter_promo, Edenflowers.Pricing.Promotion do
      description "The one-use welcome code generated when they subscribed to the newsletter."
    end

    has_many :placed_orders, Edenflowers.Orders.Order do
      description "Their placed orders, newest first. Carts never checked out are left out."
      filter expr(state == :placed)
      sort ordered_at: :desc
    end
  end

  calculations do
    calculate :can_review?, :boolean, expr(admin or reviewer) do
      description "Whether every page turns on the Option+Click picker for leaving review notes. " <>
                    "`Feedback.Note`'s policies grant the same people."
    end

    calculate :first_name, :string, {Calculations.FirstName, source: :name} do
      description "Best guess from the free-text `name`, also handling \"Smith, Jane\". Sent to Brevo."
    end

    calculate :last_name, :string, {Calculations.LastName, source: :name} do
      description "Best guess from the free-text `name`, also handling \"Smith, Jane\". Sent to Brevo."
    end

    calculate :initials, :string, {Calculations.Initials, source: :name} do
      description "One or two capital letters from `name`, shown where there's no photo."
    end

    # A user without a promo has no usage, so the `if` turns that NULL into a strict false.
    calculate :newsletter_offer_hidden?,
              :boolean,
              expr(if(newsletter_opt_in or newsletter_promo.usage > 0, true, false)) do
      description "Whether checkout stops offering the newsletter discount: they already subscribed, " <>
                    "or used their welcome code."
    end
  end

  aggregates do
    count :placed_order_count, :placed_orders do
      description "Placed orders, cancelled ones included."
    end

    max :last_ordered_at, :placed_orders, :ordered_at do
      description "When their latest order was placed. Nil without one."
    end

    first :phone_number, :placed_orders, :customer_phone_number do
      description "The phone number on their latest order. Users keep no phone number of their own, " <>
                    "and the latest order's is the freshest."

      sort ordered_at: :desc
    end

    sum :total_spent, [:placed_orders, :payments], :amount do
      description "Money received in euros, refunds taken off (see ADR 0001), which can differ from the orders' totals."
      default Decimal.new("0")
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
