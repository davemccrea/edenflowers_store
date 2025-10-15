defmodule Edenflowers.Services do
  use Ash.Domain

  resources do
    resource Edenflowers.Services.Course
    resource Edenflowers.Services.CourseRegistration
  end
end
