defmodule EdenflowersWeb.Admin.PubSubTest do
  use ExUnit.Case, async: true

  alias EdenflowersWeb.Admin.PubSub

  test "external changes warn regardless of input state and own writes leave the warning unchanged" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, stale: false, flash: %{}},
      private: %{live_temp: %{}}
    }

    own_write = %Phoenix.Socket.Broadcast{payload: %{from: self()}}
    external_write = %Phoenix.Socket.Broadcast{payload: %{}}

    refute PubSub.mark_stale(socket, own_write).assigns.stale
    warned = PubSub.mark_stale(socket, external_write)
    assert warned.assigns.stale
    assert warned.assigns.flash["info"] =~ "Saving now may overwrite"
    assert PubSub.mark_stale(warned, own_write).assigns.stale
  end

  test "a burst shares its first refresh deadline and later changes schedule another" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    # Long enough that the first timer is still pending at the second call, even
    # when the first call has to load modules.
    socket = PubSub.schedule_refresh(socket, :table, 200)

    socket = PubSub.schedule_refresh(socket, :table, 60_000)
    assert_receive {:admin_refresh, :table}, 500
    refute_receive {:admin_refresh, :table}, 20

    PubSub.schedule_refresh(socket, :table, 10)
    assert_receive {:admin_refresh, :table}, 500
  end

  test "independent refresh keys do not suppress one another" do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    |> PubSub.schedule_refresh(:first, 10)
    |> PubSub.schedule_refresh(:second, 10)

    assert_receive {:admin_refresh, :first}, 500
    assert_receive {:admin_refresh, :second}, 500
  end
end
