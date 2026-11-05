defmodule Edenflowers.Courses.CourseRegistration.Checkout do
  @moduledoc """
  The checkout on a course's page, where a customer registers their places
  and pays for them.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshRateLimiter]

  import Ash.Expr, only: [expr: 1]

  alias Edenflowers.Courses.CourseRegistration.Actions
  alias Edenflowers.Courses.CourseRegistration.Changes
  alias Edenflowers.Payments.Changes, as: PaymentChanges

  @locales Edenflowers.Locales.all()

  # Per checkout. Codes are 60 random bits, so this is against hammering, not guessing.
  rate_limit do
    backend Edenflowers.RateLimiter
    action :add_gift_voucher_with_code, limit: 10, per: :timer.minutes(15), on: :before_transaction
  end

  actions do
    # The checkout a customer is paying for on the course page, so a failed
    # payment's return can pick it up again.
    read :checkout do
      description "A pending course-page checkout by id and course, so a failed payment's return can pick it up, " <>
                    "with what its Gift voucher pays and Stripe is to charge. Never an accepted booking or a " <>
                    "legacy payment-link registration."

      get? true
      filter expr(status == :pending and is_nil(payment_link_token))
      prepare build(load: [:voucher_amount, :voucher_left_after, :stripe_amount])
    end

    action :prepare_checkout_payment, :map do
      description "Readies the PaymentIntent for a course-page checkout at its current price and returns its " <>
                    "client secret. Refuses a course that has closed or lacks room for the places."

      argument :registration_id, :uuid, allow_nil?: false
      argument :course_id, :uuid, allow_nil?: false
      run Actions.PrepareCheckoutPayment
    end

    create :register do
      description "Starts a customer's course-page checkout: a pending registration priced now, for a course " <>
                    "still open with room, finding or creating their user by email. Holds no places until paid."

      accept [:name, :email, :seats, :course_id, :locale]
      validate attribute_in(:locale, @locales)
      change Changes.UpsertUser
      change Changes.PriceBooking
      change atomic_set(:reference, expr(fragment("nextval('reference_seq')::text")))
    end

    # Going back at checkout keeps the registration, and the PaymentIntent it
    # may already have, which is brought up to the new price before paying.
    # The filter refuses a booking confirmed meanwhile at the database: a
    # payment that wins books what was registered when it landed.
    update :revise do
      description "Changes the name, email or places of an unpaid course-page checkout when the customer goes " <>
                    "back, and reprices it. Refused once confirmed or on a legacy payment-link registration."

      accept [:name, :email, :seats]
      change filter expr(status == :pending and is_nil(payment_link_token))
      change Changes.UpsertUser
      change Changes.PriceBooking
      require_atomic? false
    end

    update :add_gift_voucher_with_code do
      description "Puts the Gift voucher with this code on an unpaid course-page checkout, so Stripe charges " <>
                    "only what it doesn't cover. Nothing is spent until the booking is confirmed. Fails on an " <>
                    "unknown, expired or used-up voucher. Rate-limited: a code is money."

      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
      change filter expr(status == :pending and is_nil(payment_link_token))
      change PaymentChanges.ApplyGiftVoucher
      require_atomic? false
    end

    update :clear_gift_voucher do
      description "Takes the Gift voucher off an unpaid course-page checkout, so the card pays it all."
      change filter expr(status == :pending and is_nil(payment_link_token))
      change set_attribute(:gift_voucher_id, nil)
    end
  end
end
