defmodule EdenflowersWeb.Admin.DefaultTableView do
  @moduledoc """
  Opens an admin table on what the florist needs at first glance, such as the
  orders still to be made.

  The default view only fills in for a bare URL on the LiveView's first load.
  Once the florist clears or changes the filters, a bare URL means "show
  everything" rather than snapping back to the default.
  """
  import Phoenix.Component, only: [assign: 3]

  def handle_params(params, uri, socket, default_view) do
    params =
      if params == %{} and !socket.assigns[:default_table_view_applied?] do
        default_view
      else
        params
      end

    socket
    |> assign(:default_table_view_applied?, true)
    |> then(&Cinder.UrlSync.handle_params(params, uri, &1))
  end
end
