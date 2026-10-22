defmodule Edenflowers.Courses do
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
      define :add_registration_manually, action: :add_manually
      define :get_registration_by_id, action: :read, get_by: [:id]
      define :add_registration_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]

      define :confirm_registration_payment, action: :confirm_payment, args: [:payment_intent_id]
      define :open_registration_payment_link, action: :open_payment_link
      define :email_registration_payment_link, action: :email_payment_link
      define :email_registration_confirmation, action: :email_receipt
      define :get_registration_by_payment_link_token, action: :by_payment_link_token, args: [:token]
      define :record_registration_payment, action: :record_payment, args: [:amount, :payment_method]
      define :undo_registration_payment, action: :undo_payment, args: [:payment_id]
      define :remove_registration_seat, action: :remove_seat
      define :cancel_registration, action: :cancel
      define :release_registration_hold, action: :release_hold
    end
  end
end
