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
      define :register_for_course, action: :register
      define :add_registration_manually, action: :add_manually
      define :get_registration_by_id, action: :read, get_by: [:id]
      define :add_registration_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
      define :mark_registration_payment_cancelled, action: :mark_payment_cancelled, args: [:payment_intent_id]

      define :confirm_registration_payment, action: :confirm_payment, args: [:payment_intent_id]
      define :record_registration_stripe_refund, action: :record_stripe_refund, args: [:stripe_refund_id, :amount]
      define :mark_registration_paid, action: :mark_paid, args: [:payment_method]
      define :remove_registration_seat, action: :remove_seat
      define :cancel_registration, action: :cancel
    end
  end
end
