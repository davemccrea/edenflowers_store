defmodule EdenflowersWeb.PresenceTest do
  use ExUnit.Case, async: false

  alias EdenflowersWeb.Presence

  test "groups tabs and removes a visitor only after their last connection leaves" do
    visitor_id = Ecto.UUID.generate()
    key = "visitor:#{visitor_id}"
    first = connection(nil, visitor_id)
    second = connection(nil, visitor_id)

    eventually(fn ->
      assert Enum.count(Presence.connected_customers(), &(&1.key == key)) == 1
    end)

    stop_connection(first)
    assert Enum.any?(Presence.connected_customers(), &(&1.key == key))

    stop_connection(second)
    eventually(fn -> refute Enum.any?(Presence.connected_customers(), &(&1.key == key)) end)
  end

  test "groups signed-in customers across browsers and includes admins" do
    user = %{id: Ecto.UUID.generate(), name: "Connected customer", email: "customer@example.com", admin: false}
    first = connection(user, Ecto.UUID.generate())
    second = connection(user, Ecto.UUID.generate())
    admin_user = %{user | id: Ecto.UUID.generate(), admin: true}
    admin = connection(admin_user, Ecto.UUID.generate())

    eventually(fn ->
      assert [%{name: "Connected customer", user_id: id}] =
               Enum.filter(Presence.connected_customers(), &(&1.user_id == user.id))

      assert id == user.id
      assert Enum.any?(Presence.connected_customers(), &(&1.key == "customer:#{admin_user.id}"))
    end)

    Enum.each([first, second, admin], &stop_connection/1)
  end

  defp connection(user, visitor_id) do
    parent = self()

    pid =
      spawn_link(fn ->
        Presence.track_customer(user, visitor_id)
        send(parent, {:tracked, self()})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:tracked, ^pid}
    on_exit(fn -> send(pid, :stop) end)
    pid
  end

  defp stop_connection(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  end

  defp eventually(assertion, attempts \\ 100) do
    assertion.()
  rescue
    error in ExUnit.AssertionError ->
      if attempts > 1 do
        Process.sleep(10)
        eventually(assertion, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
