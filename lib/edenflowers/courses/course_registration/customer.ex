defmodule Edenflowers.Courses.CourseRegistration.Customer do
  @moduledoc """
  A customer's own confirmed bookings on their account page.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource

  import Ash.Expr, only: [expr: 1]

  actions do
    # Scoped to the actor by filter, not by policy: the admin bypass in policies
    # grants admins an unrestricted read, so an action named for the customer's
    # own bookings has to narrow itself or it hands Jennie everyone's.
    read :mine do
      description "The actor's own confirmed bookings, for their account page."

      filter expr(user_id == ^actor(:id) and status == :confirmed)
    end
  end
end
