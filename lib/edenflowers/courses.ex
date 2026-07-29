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
      define :list_registrations, action: :read
      define :register_for_course, action: :register
      define :get_registration_by_id, action: :read, get_by: [:id]
    end
  end
end
