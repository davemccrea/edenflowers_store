defmodule Edenflowers.Fulfillment.ShopCalendarTest do
  use Edenflowers.DataCase, async: false
  import Generator
  alias Edenflowers.Fulfillment

  test "is created on first use, open every day with same-day off" do
    Edenflowers.Repo.delete_all("shop_calendar")
    calendar = Fulfillment.get_shop_calendar!()

    assert calendar.available_days == Edenflowers.Fulfillment.Weekday.all()
    assert {calendar.enabled_dates, calendar.disabled_dates, calendar.same_day} == {[], [], false}
  end

  test "stays one row, keeping its settings" do
    closed = Fulfillment.toggle_date!(Fulfillment.get_shop_calendar!(), ~D[2030-01-01], authorize?: false)

    assert Fulfillment.get_shop_calendar!().disabled_dates == closed.disabled_dates
    assert [_one] = Ash.read!(Fulfillment.ShopCalendar)
  end

  test "same-day needs a deadline" do
    admin = generate(admin_user())
    calendar = Fulfillment.get_shop_calendar!()

    assert {:error, _} = Fulfillment.update_same_day(calendar, %{same_day: true}, actor: admin)

    assert {:ok, %{same_day: true, order_deadline: ~T[12:00:00]}} =
             Fulfillment.update_same_day(calendar, %{same_day: true, order_deadline: ~T[12:00:00]}, actor: admin)
  end

  test "every calendar update broadcasts the changed availability" do
    Phoenix.PubSub.subscribe(Edenflowers.PubSub, "shop_calendar:changed")
    admin = generate(admin_user())
    today = Edenflowers.ShopTime.today()
    date = Date.add(today, 7)
    calendar = Fulfillment.get_shop_calendar!()

    updates = [
      {:toggle_date, %{date: date}},
      {:set_weekday, %{weekday: Edenflowers.Fulfillment.Weekday.from_date(date), direction: :off}},
      {:set_week, %{week: [date], today: today, direction: :open}},
      {:update_same_day, %{same_day: true, order_deadline: ~T[12:00:00]}},
      {:reset_calendar, %{}}
    ]

    Enum.reduce(updates, calendar, fn {action, params}, calendar ->
      calendar = Ash.update!(calendar, params, action: action, actor: admin)
      assert_receive %Phoenix.Socket.Broadcast{topic: "shop_calendar:changed"}
      calendar
    end)
  end

  test "a refused update doesn't broadcast a calendar change" do
    Phoenix.PubSub.subscribe(Edenflowers.PubSub, "shop_calendar:changed")
    admin = generate(admin_user())

    assert {:error, _} =
             Fulfillment.update_same_day(Fulfillment.get_shop_calendar!(), %{same_day: true}, actor: admin)

    refute_receive %Phoenix.Socket.Broadcast{topic: "shop_calendar:changed"}
  end

  test "only an admin changes it" do
    customer = generate(admin_user(admin: false))

    assert {:error, %Ash.Error.Forbidden{}} =
             Fulfillment.toggle_date(Fulfillment.get_shop_calendar!(), ~D[2030-01-01], actor: customer)
  end
end
