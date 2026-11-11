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

      prepare build(load: [:course, :seats_held, :upcoming?, :balance, :receipt_available?, :payment_instruction])
    end
  end

  calculations do
    calculate :payment_instruction,
              :atom,
              # Use the loaded balance in Elixir rather than repeating its
              # dependent expressions in the SQL query (ADR 0007).
              fn records, _context ->
                Enum.map(records, fn record ->
                  cond do
                    Decimal.lte?(record.balance, 0) -> nil
                    record.payment_terms == :invoice -> :invoice
                    record.payment_link_open? -> :pay_now
                    true -> :at_course
                  end
                end)
              end do
      load [:balance, :payment_link_open?]
      constraints one_of: [:invoice, :pay_now, :at_course]

      description "How the customer should pay the booking's remaining balance: by invoice, an open payment " <>
                    "link, or at the course. Nil once the balance is paid."
    end
  end
end
