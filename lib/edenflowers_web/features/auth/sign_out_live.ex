defmodule EdenflowersWeb.Auth.SignOutLive do
  use EdenflowersWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_path={@current_path}>
      <section class="bg-base-100 border-base-300 mx-4 flex w-full max-w-md flex-col space-y-6 border p-8 sm:p-10">
        <%= if @current_user do %>
          <div class="space-y-2 text-center">
            <h1 class="text-xl font-semibold">{~t"Sign out"}</h1>
            <p class="text-base-content/70 text-sm">
              {~t"You're signed in as"} <span class="text-base-content break-all font-medium">{@current_user.email}</span>.
            </p>
          </div>

          <div class="flex flex-col space-y-4">
            <.button href={~p"/sign-out"} method="delete" variant="primary" size="lg">
              {~t"Sign out"}
              <.icon name="hero-arrow-right-start-on-rectangle" />
            </.button>

            <div class="text-center text-sm">
              <.button navigate={stay_path(@current_user)} variant="text">
                {~t"Stay signed in"}
              </.button>
            </div>
          </div>
        <% else %>
          <div class="space-y-2 text-center">
            <h1 class="text-xl font-semibold">{~t"You're signed out"}</h1>
            <p class="text-base-content/70 text-sm">
              {~t"There's no account signed in on this device."}
            </p>
          </div>

          <.button navigate={~p"/"} variant="primary" size="lg">
            {~t"Back to the shop"}
            <.icon name="hero-arrow-right" />
          </.button>
        <% end %>
      </section>
    </Layouts.auth>
    """
  end

  defp stay_path(%{admin: true}), do: ~p"/admin"
  defp stay_path(_user), do: ~p"/"
end
