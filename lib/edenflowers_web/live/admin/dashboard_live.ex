defmodule EdenflowersWeb.Admin.DashboardLive do
  use EdenflowersWeb, :live_view

  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Admin")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path}>
      <div class="container mx-auto py-10">
        <header class="mb-8">
          <h1 class="page-title">Admin</h1>
        </header>

        <div class="grid grid-cols-2 gap-4 max-w-lg">
          <.link navigate={~p"/admin/expenses"} class="card bg-base-200 hover:bg-base-300 p-6">
            <h2 class="font-semibold">Expenses</h2>
            <p class="text-sm text-base-content/55 mt-1">Review and correct extracted expenses</p>
          </.link>
          <.link navigate={~p"/admin/fulfillments"} class="card bg-base-200 hover:bg-base-300 p-6">
            <h2 class="font-semibold">Fulfillment Calendar</h2>
            <p class="text-sm text-base-content/55 mt-1">Manage delivery availability</p>
          </.link>
          <.link href="/admin/oban" class="card bg-base-200 hover:bg-base-300 p-6">
            <h2 class="font-semibold">Oban</h2>
            <p class="text-sm text-base-content/55 mt-1">Background job dashboard</p>
          </.link>
          <.link href="/admin/ash" class="card bg-base-200 hover:bg-base-300 p-6">
            <h2 class="font-semibold">AshAdmin</h2>
            <p class="text-sm text-base-content/55 mt-1">Data management</p>
          </.link>
        </div>
      </div>
    </Layouts.admin>
    """
  end
end
