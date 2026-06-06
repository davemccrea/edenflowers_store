defmodule Edenflowers.Workers.SendDriverRouteEmailTest do
  use Edenflowers.DataCase
  import Generator
  import Swoosh.TestAssertions

  alias Edenflowers.Dispatch
  alias Edenflowers.HereTourPlanning.{Assignment, Plan, Stop}
  alias Edenflowers.Workers.SendDriverRouteEmail

  @date ~D[2026-06-07]

  defp publish_route(driver) do
    order =
      generate(
        order(
          state: :placed,
          payment_status: :paid,
          fulfillment_status: :pending,
          fulfillment_method: :delivery,
          fulfillment_date: @date,
          position: "63.1,21.6"
        )
      )

    admin = generate(admin_user())

    assignment = %Assignment{
      vehicle_id: driver.id,
      stops: [%Stop{order_id: order.id, sequence: 1, leg_distance: 3000, leg_duration: 600}],
      total_distance: 3000,
      total_driving_duration: 600,
      total_service_duration: 300
    }

    {:ok, result} =
      Dispatch.publish(%Plan{assignments: [assignment]}, %{
        delivery_date: @date,
        published_by_user_id: admin.id
      })

    hd(result.routes)
  end

  test "delivers the route email to the driver with the date-bound secret link" do
    driver = generate(driver(name: "Erik", email: "erik@example.com", preferred_locale: "en-GB"))
    entry = publish_route(driver)

    assert :ok =
             perform_job(SendDriverRouteEmail, %{
               "delivery_route_id" => entry.route.id,
               "token" => entry.raw_token
             })

    assert_email_sent(fn email ->
      assert email.to == [{"", "erik@example.com"}]
      assert email.text_body =~ "Erik"
      assert email.text_body =~ "/deliveries/#{entry.raw_token}"
      assert email.html_body in [nil, ""]
    end)
  end

  test "sends in the driver's preferred locale without error" do
    driver = generate(driver(preferred_locale: "sv-FI"))
    entry = publish_route(driver)

    assert :ok =
             perform_job(SendDriverRouteEmail, %{
               "delivery_route_id" => entry.route.id,
               "token" => entry.raw_token
             })

    assert_email_sent()
  end

  test "is idempotent — re-enqueuing the same route collapses to one job" do
    driver = generate(driver())
    entry = publish_route(driver)

    # Publication already enqueued one job; a duplicate enqueue must not add another.
    {:ok, _} =
      SendDriverRouteEmail.enqueue(%{
        "delivery_route_id" => entry.route.id,
        "token" => entry.raw_token
      })

    assert all_enqueued(worker: SendDriverRouteEmail)
           |> Enum.filter(&(&1.args["delivery_route_id"] == entry.route.id))
           |> length() == 1
  end
end
