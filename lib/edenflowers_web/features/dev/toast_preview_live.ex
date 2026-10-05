defmodule EdenflowersWeb.Dev.ToastPreviewLive do
  @moduledoc """
  Dev-only playground for previewing flash toasts inside the storefront layout.
  """
  use EdenflowersWeb, :live_view

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Toast preview")}
  end

  def handle_event("info", _params, socket) do
    {:noreply, put_flash(socket, :info, "Added to cart.")}
  end

  def handle_event("error", _params, socket) do
    {:noreply, put_flash(socket, :error, "Could not save the product.")}
  end

  def handle_event("long_error", _params, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "Your payment didn't go through. Please try again or choose another payment method."
     )}
  end

  def handle_event("both", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Order marked as fulfilled.")
     |> put_flash(:error, "Corrections saved, but the expense could not be marked as reviewed.")}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, clear_flash(socket)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <h1 class="page-title mb-8">Toast preview</h1>

        <div class="flex flex-col gap-8">
          <section class="flex flex-col gap-3">
            <h2 class="font-semibold">Server flashes</h2>
            <div class="flex flex-wrap gap-3">
              <.button phx-click="info">Info</.button>
              <.button phx-click="error">Error</.button>
              <.button phx-click="long_error">Long error</.button>
              <.button phx-click="both">Info + error</.button>
            </div>
          </section>

          <section class="flex flex-col gap-3">
            <h2 class="font-semibold">Connection toasts</h2>
            <div class="flex flex-wrap gap-3">
              <.button phx-click={reveal("#client-error")}>Connection lost</.button>
              <.button phx-click={reveal("#server-error")}>Something went wrong</.button>
            </div>
          </section>

          <section class="flex flex-col gap-3">
            <h2 class="font-semibold">Reset</h2>
            <div class="flex flex-wrap gap-3">
              <.button
                variant="ghost"
                phx-click={JS.push("clear") |> conceal("#client-error") |> conceal("#server-error")}
              >
                Clear all
              </.button>
            </div>
          </section>

          <p class="text-base-content/70 max-w-prose text-sm">
            Info toasts dismiss themselves after five seconds. Sign in as an admin to see the toasts lift above the Admin shortcut pill.
          </p>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp reveal(selector) do
    selector |> show() |> JS.remove_attribute("hidden", to: selector)
  end

  defp conceal(js, selector) do
    js |> hide(selector) |> JS.set_attribute({"hidden", ""}, to: selector)
  end
end
