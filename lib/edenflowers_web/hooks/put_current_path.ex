defmodule EdenflowersWeb.Hooks.PutCurrentPath do
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    socket =
      Phoenix.LiveView.attach_hook(socket, :put_current_path, :handle_params, fn _params, uri, socket ->
        path = URI.parse(uri).path || "/"
        {:cont, assign(socket, :current_path, path)}
      end)

    {:cont, socket}
  end
end
