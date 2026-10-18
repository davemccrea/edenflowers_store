defmodule Edenflowers.Fulfillment.ShopCalendarTest do
  use Edenflowers.DataCase, async: true
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

  test "only an admin changes it" do
    customer = generate(admin_user(admin: false))

    assert {:error, %Ash.Error.Forbidden{}} =
             Fulfillment.toggle_date(Fulfillment.get_shop_calendar!(), ~D[2030-01-01], actor: customer)
  end
end
