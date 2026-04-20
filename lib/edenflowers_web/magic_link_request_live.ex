defmodule EdenflowersWeb.MagicLinkRequestLive do
  use EdenflowersWeb, :live_view

  require Logger

  alias AshAuthentication.Info
  alias Edenflowers.Accounts.User

  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(strategy: Info.strategy!(User, :magic_link))
      |> assign(current_tenant: session["tenant"])
      |> assign(context: session["context"] || %{})
      |> assign(email: nil)
      |> assign_blank_form()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <section class="bg-base-100 flex w-full max-w-lg flex-col space-y-4 p-8 shadow-lg">
        <h2 class="text-center text-lg font-bold">
          {~t"Sign in to your account"}
        </h2>

        <%= if @email do %>
          <p class="text-center text-sm">
            {~t"🥳 A magic link was sent to #{@email}."}
            <br />
            {~t"Please check your email to complete sign in."}
          </p>
        <% else %>
          <.form class="flex w-full flex-col space-y-4" for={@form} phx-change="change" phx-submit="submit" method="POST">
            <.input autofocus field={@form[:email]} label={~t"Email"} placeholder={~t"info@edenflowers.fi"} />

            <button type="submit" class="btn btn-primary btn-lg">
              {~t"Get Magic Link"}
              <.icon name="hero-arrow-right" />
            </button>
          </.form>
        <% end %>
      </section>
    </Layouts.auth>
    """
  end

  def handle_event("change", %{"user" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("submit", %{"user" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      :ok ->
        {:noreply, socket |> assign(email: params["email"])}

      {:ok, _} ->
        {:noreply, socket |> assign(email: params["email"])}

      {:error, form} ->
        {:noreply, socket |> assign(form: form) |> error_toast()}
    end
  end

  defp assign_blank_form(%{assigns: %{strategy: strategy, current_tenant: current_tenant, context: context}} = socket) do
    domain = Info.authentication_domain!(strategy.resource)
    subject_name = Info.authentication_subject_name!(strategy.resource)

    form =
      strategy.resource
      |> AshPhoenix.Form.for_action(strategy.request_action_name,
        domain: domain,
        as: subject_name |> to_string(),
        id: "magic-link-request",
        tenant: current_tenant,
        transform_errors: fn _source, error -> error end,
        context:
          Ash.Helpers.deep_merge_maps(context, %{
            strategy: strategy,
            private: %{ash_authentication?: true}
          })
      )
      |> to_form()

    assign(socket, form: form)
  end

  defp error_toast(socket) do
    toast =
      EdenflowersWeb.LiveToast.new(
        :warning,
        ~t"Error sending magic link. Please try again later."
      )

    push_event(socket, "toast:show", toast)
  end
end
