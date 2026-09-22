defmodule Edenflowers.Courses do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Courses.Course do
      define :list_courses, action: :read
      define :get_course_by_id, action: :read, get_by: [:id]
      define :create_course, action: :create
      define :list_upcoming_courses, action: :upcoming
      define :list_past_courses, action: :past
    end

    resource Edenflowers.Courses.CourseRegistration do
      define :list_my_registrations, action: :mine
      define :register_for_course, action: :register
      define :get_registration_by_id, action: :read, get_by: [:id]
      define :add_registration_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
      define :confirm_registration_payment, action: :confirm_payment
      define :mark_registration_receipt_emailed, action: :mark_receipt_emailed, args: [:receipt_sha256]
      define :cancel_registration, action: :cancel
    end
  end
end
