defmodule EdenflowersWeb.Admin.AccountLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components

  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.LiveUserAuth, :live_admin_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, ~t"Account")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page width="narrow">
        <.admin_page_header title={~t"Account"}>
          <:subtitle>{~t"Manage your signed-in admin session."}</:subtitle>
        </.admin_page_header>

        <section class="bg-base-100 border-base-300/70 rounded-lg border p-4 sm:p-5">
          <div class="mb-5 flex items-center gap-3">
            <span class="bg-primary/10 text-primary inline-flex h-12 w-12 shrink-0 items-center justify-center rounded-full text-base font-semibold">
              {user_initials(@current_user)}
            </span>
            <div class="min-w-0">
              <h2 class="text-base-content truncate text-lg font-semibold">
                {display_name(@current_user)}
              </h2>
              <p class="text-base-content/65 truncate text-sm">{user_email(@current_user)}</p>
            </div>
          </div>

          <dl class="divide-base-300/70 divide-y">
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt class="text-base-content/60 text-sm">{~t"Name"}</dt>
              <dd class="text-base-content text-sm">{display_name(@current_user)}</dd>
            </div>
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt class="text-base-content/60 text-sm">{~t"Email"}</dt>
              <dd class="text-base-content break-all text-sm">{user_email(@current_user)}</dd>
            </div>
            <div class="grid gap-1 py-3 sm:grid-cols-[8rem_1fr] sm:gap-4">
              <dt class="text-base-content/60 text-sm">{~t"Access"}</dt>
              <dd class="text-base-content text-sm">{~t"Admin"}</dd>
            </div>
          </dl>

          <div class="border-base-300/70 mt-5 border-t pt-5">
            <.link href={~p"/sign-out"} method="delete" class="btn btn-outline btn-sm">
              <.icon name="hero-arrow-right-start-on-rectangle" class="h-4 w-4" />
              {~t"Sign out"}
            </.link>
          </div>
        </section>
      </.admin_page>
    </Layouts.admin>
    """
  end

  defp display_name(user) do
    user
    |> Map.get(:name)
    |> case do
      name when is_binary(name) ->
        name = String.trim(name)
        if name == "", do: user_email(user), else: name

      _ ->
        user_email(user)
    end
  end

  defp user_email(user), do: user |> Map.get(:email) |> to_string()

  defp user_initials(user) do
    user
    |> Map.get(:initials)
    |> case do
      initials when is_binary(initials) ->
        initials = String.trim(initials)
        if initials == "", do: fallback_initial(user), else: initials

      _ ->
        fallback_initial(user)
    end
  end

  defp fallback_initial(user),
    do: user |> user_email() |> String.first() |> Kernel.||("A") |> String.upcase()
end
