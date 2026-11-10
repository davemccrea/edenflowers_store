defmodule EdenflowersWeb.Admin.PubSub do
  @moduledoc """
  Shared helpers for admin LiveViews that follow Ash PubSub notifications.

  A list page subscribes to its collection topic and refreshes the table. A
  burst of notifications, such as a subscription job or a bank sync, is
  coalesced into one refresh with `schedule_refresh/3`.

  Editors mark external changes stale and use the existing flash notification
  so the warning is also visible when the editor notice is off-screen.
  """

  use GettextSigils,
    backend: EdenflowersWeb.Gettext,
    sigils: [domain: "admin"]

  # Tests only need the timer to fire, not the production coalescing window.
  @refresh_delay if Mix.env() == :test, do: 10, else: 120

  def subscribe(topics) do
    Enum.each(topics, &Edenflowers.Events.subscribe/1)
  end

  @doc "Warns about external changes regardless of input state; never restricts saving."
  def mark_stale(socket, notification, key \\ :stale)

  def mark_stale(socket, %Phoenix.Socket.Broadcast{payload: %{from: from}}, _key) when from == self(),
    do: socket

  def mark_stale(socket, _notification, key) do
    socket
    |> Phoenix.Component.assign(key, true)
    |> Phoenix.LiveView.put_flash(
      :info,
      ~t"Saved data changed elsewhere. Saving now may overwrite those changes. Reload to use the latest saved data, or save anyway."
    )
  end

  @doc """
  Sends `{:admin_refresh, key}` after `delay` ms unless one is already pending.

  Later notifications share the pending refresh rather than postponing it.
  """
  def schedule_refresh(socket, key, delay \\ @refresh_delay) do
    timers = socket.assigns[:admin_pub_sub_timers] || %{}

    ref = Map.get(timers, key)

    if ref && Process.read_timer(ref) do
      socket
    else
      ref = Process.send_after(self(), {:admin_refresh, key}, delay)
      Phoenix.Component.assign(socket, :admin_pub_sub_timers, Map.put(timers, key, ref))
    end
  end
end
