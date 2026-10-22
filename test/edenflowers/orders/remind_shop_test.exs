defmodule Edenflowers.Orders.RemindShopTest do
  use Edenflowers.DataCase, async: true
  import Swoosh.TestAssertions
  import Generator

  alias Edenflowers.Orders.Schedulers.RemindShop, as: ScheduleReminders
  alias Edenflowers.Orders.Workers.EmailShop
  alias Edenflowers.Orders.Workers.RemindShop

  test "an order starting within the hour reminds the shop" do
    order = starting_in(30, order_reference: "1042")

    assert order.id in scheduled_reminders()
    assert {:ok, _order} = perform_job(RemindShop, %{"primary_key" => %{"id" => order.id}})

    assert Ash.reload!(order, authorize?: false).shop_reminded_at
    assert_enqueued(worker: EmailShop, args: %{"notice" => "reminder", "order_id" => order.id})
    assert :ok = perform_job(EmailShop, %{"notice" => "reminder", "order_id" => order.id})

    assert_email_sent(fn email ->
      assert email.subject =~ ~r/^Avhämtning kl\. \d{1,2}\.\d\d, beställning 1042$/
      assert email.text_body =~ ~r/^Öppna beställningen:\n/
    end)
  end

  test "no reminder for an order outside the hour, without a time, done, or already reminded" do
    orders = [
      starting_in(90),
      starting_in(-10),
      starting_in(30, fulfillment_time_start: nil),
      starting_in(30, fulfillment_status: :fulfilled),
      starting_in(30, shop_reminded_at: DateTime.utc_now(:second))
    ]

    scheduled = scheduled_reminders()
    for order <- orders, do: refute(order.id in scheduled)
  end

  defp starting_in(minutes, attrs \\ []) do
    starts = DateTime.add(Edenflowers.ShopTime.now(), minutes, :minute)

    defaults = [
      fulfillment_date: DateTime.to_date(starts),
      fulfillment_time_start: starts |> DateTime.to_time() |> Time.truncate(:second)
    ]

    placed_order(Keyword.merge(defaults, attrs))
  end

  defp scheduled_reminders do
    assert :ok = perform_job(ScheduleReminders, %{})
    for job <- all_enqueued(worker: RemindShop), do: job.args["primary_key"]["id"]
  end
end
