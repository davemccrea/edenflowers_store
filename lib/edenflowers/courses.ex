defmodule Edenflowers.Courses do
  @moduledoc """
  Entry point for florist courses and their bookings.

  `Course` defines the event, capacity, and price. A `CourseRegistration` books
  places once paid, then records payments, refunds or cancellation.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Courses.Course do
      define :get_course_by_id, action: :read, get_by: [:id]
      define :list_upcoming_courses, action: :upcoming
    end

    resource Edenflowers.Courses.CourseRegistration do
      define :list_my_registrations, action: :mine
      define :list_unsettled_registrations, action: :unsettled
      define :register_for_course, action: :register
      define :get_checkout_registration, action: :checkout, get_by: [:id, :course_id]
      define :revise_registration, action: :revise
      define :add_registration_manually, action: :add_manually
      define :get_registration_by_id, action: :read, get_by: [:id]
      define :add_registration_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]

      define :confirm_registration_payment, action: :confirm_payment, args: [:payment_intent_id]
      define :open_registration_payment_link, action: :open_payment_link
      define :email_registration_payment_link, action: :email_payment_link
      define :send_registration_payment_reminder, action: :send_payment_reminder
      define :email_registration_confirmation, action: :email_receipt
      define :get_registration_by_payment_link_token, action: :by_payment_link_token, args: [:token]
      define :undo_registration_payment, action: :undo_payment, args: [:payment_id]
      define :remove_registration_seat, action: :remove_seat
      define :cancel_registration, action: :cancel
      define :discard_registration, action: :discard_or_retain, args: [:id]
    end
  end
end
