defmodule Edenflowers.Accounts.User.LogsOutSelf do
  @moduledoc """
  Authorizes `log_out_everywhere` only for the user it signs out. A generic
  action has no row to filter, so the check compares the actor with the
  action's `user` argument.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is the user being signed out"

  @impl true
  def match?(%{id: id}, %{subject: %Ash.ActionInput{arguments: %{user: %{id: id}}}}, _opts), do: true
  def match?(_actor, _context, _opts), do: false
end

defmodule Edenflowers.Accounts.User do
  @moduledoc """
  Customer and admin identity. Email one-time codes authenticate users; the same record links orders, course bookings, and newsletter preferences.
  """

  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshAuthentication, AshRateLimiter, AshAdmin.Resource]

  alias Edenflowers.Accounts.Calculations
  alias Edenflowers.Accounts.Changes
  alias Edenflowers.Accounts.Workers.PushNewsletterSubscriber
  alias Edenflowers.Events
  alias Edenflowers.Types.Email

  # The sign-in token's lifetime, which the session cookie and the privacy notice share.
  @session_days 365

  def session_days, do: @session_days

  authentication do
    add_ons do
      log_out_everywhere do
      end
    end

    tokens do
      enabled? true
      token_resource Edenflowers.Accounts.Token
      signing_secret Edenflowers.Secrets
      token_lifetime {@session_days, :days}
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      otp do
        identity_field :email
        registration_enabled? true
        brute_force_strategy :rate_limit
        otp_characters :digits_only
        otp_length 8

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

    # Keyed on the lowercased address: the email is matched case-insensitively,
    # so "Info@" and "info@" are one account and must share one allowance.
    action :request_otp,
      limit: 5,
      per: :timer.minutes(15),
      key: fn input -> "otp:request:#{String.downcase(to_string(input.arguments[:email]))}" end

    action :sign_in_with_otp,
      limit: 5,
      per: :timer.minutes(10),
      key: fn input -> "otp:sign_in:#{String.downcase(to_string(input.arguments[:email]))}" end

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
      description "Finds or creates the user for a customer's email as a checkout, order or booking takes it. " <>
                    "The name only fills an account that has none: the email isn't verified, so whoever types " <>
                    "it must not rename someone else's account."

      accept [:email, :name]
      upsert? true
      upsert_identity :unique_email
      # On conflict `name` is the existing row's and `atomic_ref(:name)` the typed one.
      change atomic_update(:name, expr(if is_nil(name), do: ^atomic_ref(:name), else: name))
      # Without it the conflict sets the identity key, so the typed casing would replace the account's.
      change atomic_update(:email, expr(email))
    end

    update :update do
      description "Changes a user's name, or their newsletter opt-in with the language it applies to. A changed " <>
                    "opt-in is queued for MailerLite. The newsletter sync also uses it to opt out anyone who " <>
                    "unsubscribed in MailerLite."

      accept [:name, :newsletter_opt_in, :locale]
      require_atomic? false

      change after_action(fn _changeset, user, _context ->
               with {:ok, _job} <- PushNewsletterSubscriber.enqueue(user), do: {:ok, user}
             end),
             where: changing(:newsletter_opt_in)
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
      description "Opts an email in to the newsletter, creating the user if needed. A first-time subscriber gets " <>
                    "their one-use welcome code at once, so checkout can apply it, and is queued the welcome " <>
                    "email with it. A subscriber who already has a code keeps it and is emailed the " <>
                    "already-subscribed wording instead. Either way the opt-in is pushed to MailerLite."

      accept [:email, :locale]
      upsert? true
      upsert_identity :unique_email
      change set_attribute(:newsletter_opt_in, true)
      change Changes.GiveNewsletterWelcome
    end

    update :update_avatar do
      description "Stores an uploaded photo for the admin's account page and back office, in the database itself. " <>
                    "The content type comes from the file name's extension, which the upload has already checked; " <>
                    "the type the browser reports is untrusted."

      argument :filename, :string do
        description "The uploaded file's name, used only for its extension."
        allow_nil? false
      end

      accept [:avatar]
      require_atomic? false

      change fn changeset, _context ->
        filename = Ash.Changeset.get_argument(changeset, :filename)
        Ash.Changeset.change_attribute(changeset, :avatar_content_type, MIME.from_path(filename))
      end
    end

    update :update_admin_appearance do
      description "Saves how the back office looks for this admin, as set on their account page's colour " <>
                    "picker: the hue, intensity and lightness of the sidebar and buttons, and the sidebar's grain."

      accept [:admin_hue, :admin_chroma, :admin_lightness, :admin_grain]
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
                    "are left out. Without a term, every customer, so the most recent come first."

      argument :term, :ci_string do
        description "Part of the name or email, any case. Nil for every customer."
      end

      filter expr(
               exists(placed_orders, true) and
                 (is_nil(^arg(:term)) or contains(name, ^arg(:term)) or contains(email, ^arg(:term)))
             )

      prepare build(sort: [last_ordered_at: :desc])
    end

    read :top_customers do
      description "The customers Jennie sees before she types in a customer picker, so whoever she's likely " <>
                    "entering is a click away: most orders in the last year first, then most spent."

      filter expr(exists(placed_orders, true))

      prepare build(sort: [recent_order_count: :desc, total_spent: :desc, last_ordered_at: :desc], limit: 10)
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

    read :newsletter_subscribers do
      description "Everyone sent to MailerLite, with the fields it gets: newsletter subscribers only, so customers " <>
                    "who never opted in have no profile there (privacy policy)."

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

    policy action(:log_out_everywhere) do
      authorize_if __MODULE__.LogsOutSelf
    end
  end

  # The admin's customer pages show the name, email, newsletter choice and
  # order aggregates. Avatar and Stripe bookkeeping changes can't affect them.
  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, Events.admin_customers()
    publish_all :create, Events.admin_customer(:id)

    publish_all :update, Events.admin_customers(),
      except: [
        :ensure_stripe_customer,
        :forget_stripe_customer,
        :request_email_change,
        :update_avatar,
        :remove_avatar,
        :update_admin_appearance,
        :set_newsletter_promo
      ]

    publish_all :update, Events.admin_customer(:id),
      except: [
        :ensure_stripe_customer,
        :forget_stripe_customer,
        :request_email_change,
        :set_newsletter_promo
      ]
  end

  # Per-visitor limits on top of the per-email ones above, which can't stop one
  # visitor trying many addresses. `rate_limit` takes one entry per action, so
  # these are added directly. The address comes from EdenflowersWeb.Plugs.PutClientIp
  # (the `/auth` routes) or OtpSignInLive; callers outside the web have none.
  preparations do
    prepare {AshRateLimiter.Preparation,
             action: :request_otp,
             limit: 10,
             per: :timer.minutes(15),
             key: fn input -> "otp:request:ip:#{input.context[:client_ip]}" end},
            on: :action,
            where: fn input, _context -> if input.context[:client_ip], do: :ok, else: {:error, "no client IP"} end
  end

  changes do
    change {AshRateLimiter.Change,
            action: :sign_in_with_otp,
            limit: 20,
            per: :timer.minutes(10),
            key: fn changeset -> "otp:sign_in:ip:#{changeset.context[:client_ip]}" end},
           on: :create,
           where: fn changeset, _context ->
             if changeset.context[:client_ip], do: :ok, else: {:error, "no client IP"}
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
      description "Whether they get the newsletter, which is sent from MailerLite."
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

    attribute :admin_hue, :integer do
      description "Hue in degrees (OKLCH) of this admin's back office colour: the sidebar, phone topbar and " <>
                    "primary buttons. 152 is the shop's forest green."

      constraints min: 0, max: 360
      default 152
      allow_nil? false
      public? true
    end

    attribute :admin_chroma, :integer do
      description "Intensity of this admin's back office colour, as OKLCH chroma in thousandths: 0 is grey, " <>
                    "140 the most vivid. 50 is the shop's forest green."

      constraints min: 0, max: 140
      default 50
      allow_nil? false
      public? true
    end

    attribute :admin_lightness, :integer do
      description "Lightness (OKLCH percent) of this admin's sidebar. Primary buttons sit about 11 points " <>
                    "lighter. The range keeps the sidebar's white text and the buttons' text readable."

      constraints min: 18, max: 36
      default 26
      allow_nil? false
      public? true
    end

    attribute :admin_grain, :integer do
      description "How much film grain this admin's back office sidebar has, from 0 (none) to 100 (heaviest)."
      constraints min: 0, max: 100
      default 60
      allow_nil? false
      public? true
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
    calculate :matches?,
              :boolean,
              expr(contains(name, ^arg(:term)) or contains(email, ^arg(:term))) do
      description "The admin customers search, case-insensitive: whether the term appears in the name or email."
      argument :term, :ci_string, allow_nil?: false
    end

    calculate :can_review?, :boolean, expr(admin or reviewer) do
      description "Whether every page turns on the Option+Click picker for leaving review notes. " <>
                    "`Feedback.Note`'s policies grant the same people."
    end

    calculate :first_name, :string, {Calculations.NamePart, source: :name, part: :first} do
      description "Best guess from the free-text `name`. Sent to MailerLite."
    end

    calculate :last_name, :string, {Calculations.NamePart, source: :name, part: :last} do
      description "Best guess from the free-text `name`. Sent to MailerLite."
    end

    calculate :initials, :string, {Calculations.NamePart, source: :name, part: :initials, fallback: :email} do
      description "One or two capital letters from `name`, or the email's first, shown where there's no photo."
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

    count :recent_order_count, :placed_orders do
      description "Placed orders in the last 12 months, cancelled ones included. Ranks the top customers."
      filter expr(ordered_at > ago(12, :month))
    end

    max :last_ordered_at, :placed_orders, :ordered_at do
      description "When their latest order was placed. Nil without one."
    end

    first :phone_number, :placed_orders, :customer_phone_number do
      description "The phone number on their latest order. Users keep no phone number of their own, " <>
                    "and the latest order's is the freshest."

      sort ordered_at: :desc
    end

    first :order_locale, :placed_orders, :locale do
      description "The language of their latest order, which an invoice to them is written in. Users keep only " <>
                    "a newsletter language of their own."

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
