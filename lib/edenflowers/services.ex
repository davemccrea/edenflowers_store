defmodule Edenflowers.Services do
  use Ash.Domain,
    otp_app: :edenflowers

  resources do
    resource Edenflowers.Services.Course
    resource Edenflowers.Services.CourseRegistration
  end
end
