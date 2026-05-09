defmodule Edenflowers.Services do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Services.Course
    resource Edenflowers.Services.CourseRegistration
  end
end
