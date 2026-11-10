defmodule EdenflowersWeb.Admin.DetailRefreshTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator

  alias Edenflowers.Events
  alias EdenflowersWeb.Admin.CourseDetailLive
  alias EdenflowersWeb.Admin.CustomerDetailLive
  alias EdenflowersWeb.Admin.OrderDetailLive
  alias EdenflowersWeb.Admin.SubscriptionDetailLive
  alias EdenflowersWeb.QueryCounter

  setup :log_in_admin

  test "detail notifications only warn without reading or replacing page data", %{admin: admin} do
    course = generate(course())
    customer = generate(admin_user(admin: false))
    placed_order(user_id: customer.id)
    subscription = generate(subscription())
    order = placed_order()

    for {module, id, topics} <- [
          {CourseDetailLive, course.id, [Events.admin_course(course.id), Events.admin_bookings()]},
          {CustomerDetailLive, customer.id,
           [Events.admin_customer(customer.id), Events.admin_orders(), Events.admin_subscriptions()]},
          {SubscriptionDetailLive, subscription.id,
           [Events.admin_subscription(subscription.id), Events.admin_orders(), Events.shop_calendar_changed()]},
          {OrderDetailLive, order.id, [Events.admin_order(order.id), Events.admin_orders(), Events.admin_pass_it_on()]}
        ] do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, current_user: admin, flash: %{}},
        private: %{live_temp: %{}}
      }

      {:ok, socket} = module.mount(%{"id" => id}, %{}, socket)
      counter = QueryCounter.track(self())

      pending =
        Enum.reduce(topics ++ topics, socket, fn topic, socket ->
          notification = %Phoenix.Socket.Broadcast{topic: Events.topic(topic), payload: %{}}
          {:noreply, socket} = module.handle_info(notification, socket)
          socket
        end)

      assert QueryCounter.count(counter) == 0
      assert pending.assigns.stale

      assert Map.drop(pending.assigns, [:__changed__, :flash, :stale]) ==
               Map.drop(socket.assigns, [:__changed__, :flash, :stale])

      refute_receive {:admin_refresh, _}, 20

      own_write = %Phoenix.Socket.Broadcast{payload: %{from: self()}}
      {:noreply, unchanged} = module.handle_info(own_write, socket)
      assert unchanged.assigns == socket.assigns

      if module == OrderDetailLive do
        notification = %Phoenix.Socket.Broadcast{
          topic: Events.topic(Events.admin_orders()),
          event: "record_receipt_email_failure",
          payload: %{}
        }

        {:noreply, warned} = module.handle_info(notification, socket)
        assert warned.assigns.stale
        refute warned.assigns.flash["error"]
      end
    end
  end
end
