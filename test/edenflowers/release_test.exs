defmodule Edenflowers.ReleaseTest do
  use Edenflowers.DataCase, async: true

  import Generator

  test "allows deployment when all course registrations use supported states" do
    generate(course_registration(status: :pending))
    generate(course_registration(status: :confirmed))
    generate(course_registration(status: :cancelled))

    assert :ok = Edenflowers.Release.check_course_registration_states!(Edenflowers.Repo)
  end

  test "blocks deployment without changing legacy course registrations" do
    registration = generate(course_registration())

    Edenflowers.Repo.query!(
      "UPDATE course_registrations SET status = 'awaiting_payment' WHERE id = $1",
      [Ecto.UUID.dump!(registration.id)]
    )

    assert_raise RuntimeError, ~r/Deployment blocked: 1 course registrations/, fn ->
      Edenflowers.Release.check_course_registration_states!(Edenflowers.Repo)
    end

    assert %{rows: [["awaiting_payment"]]} =
             Edenflowers.Repo.query!("SELECT status FROM course_registrations WHERE id = $1", [
               Ecto.UUID.dump!(registration.id)
             ])
  end

  test "gives a subscription started before delivery days the weekday of its next date" do
    # Next date on a Thursday.
    thursday = Date.add(~D[2026-01-01], 7 * 60)
    subscription = generate(subscription(next_fulfillment_date: thursday))

    Edenflowers.Repo.query!("UPDATE subscriptions SET delivery_day = NULL WHERE id = $1", [
      Ecto.UUID.dump!(subscription.id)
    ])

    assert :ok = Edenflowers.Release.assign_missing_delivery_days!(Edenflowers.Repo)

    assert Ash.reload!(subscription, authorize?: false).delivery_day == :thursday
  end
end
