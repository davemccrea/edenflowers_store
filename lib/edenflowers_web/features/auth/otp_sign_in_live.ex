defmodule EdenflowersWeb.Auth.OtpSignInLive do
  use EdenflowersWeb, :live_view

  alias AshAuthentication.Info
  alias Edenflowers.Accounts.User

  # Seconds the user must wait between resend attempts. Server-side
  # AshRateLimiter on :request_otp is the safety net (5 / 15 min); this is
  # purely a UX brake so users don't burn through their quota.
  @resend_cooldown_seconds 30

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(strategy: Info.strategy!(User, :otp))
      |> assign(google_strategy: Info.strategy!(User, :google))
      |> reset_state()

    # Set by AuthController.failure/3 after a wrong code, so the user lands
    # back on the code step instead of having to request a new code. Not
    # cleared here: the connected mount reads the same flash again.
    {:ok, assign(socket, email: Phoenix.Flash.get(socket.assigns.flash, :otp_email))}
  end

  # The code step keeps the email in the URL so switching language, which
  # reloads the page, lands back on it. current_path carries the query
  # because the locale links redirect back to it.
  def handle_params(params, uri, socket) do
    socket =
      case params do
        %{"email" => email} when email != "" -> assign(socket, email: email)
        _ -> socket
      end

    current_path =
      case URI.parse(uri) do
        %URI{path: path, query: nil} -> path
        %URI{path: path, query: query} -> path <> "?" <> query
      end

    {:noreply, assign(socket, current_path: current_path)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_path={@current_path}>
      <section class="bg-base-100 border-base-300 mx-4 flex w-full max-w-md flex-col space-y-6 border p-8 sm:p-10">
        <%= if @email do %>
          <div class="space-y-2 text-center">
            <h1 class="text-xl font-semibold">{~t"Check your email"}</h1>
            <p class="text-base-content/70 text-sm">
              {~t"We sent a 6-digit code to"} <span class="text-base-content break-all font-medium">{@email}</span>. {~t"It expires in 10 minutes."}
            </p>
          </div>

          <.form
            class="flex w-full flex-col space-y-4"
            for={@sign_in_form}
            phx-submit="verify"
            method="POST"
            phx-trigger-action={@trigger_action}
            action={~p"/auth/user/otp/sign_in"}
          >
            <%!-- Mirrors the email so the form-trigger handoff carries it through. --%>
            <input type="hidden" name="user[email]" value={@email} />

            <.input
              autofocus
              field={@sign_in_form[:otp]}
              label={~t"Sign-in code"}
              autocomplete="one-time-code"
              inputmode="numeric"
              maxlength="6"
              pattern="[0-9]{6}"
              spellcheck="false"
            />

            <.button type="submit" variant="primary" size="lg">
              {~t"Sign in"}
              <.icon name="hero-arrow-right" />
            </.button>
          </.form>

          <div class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-sm">
            <%= if @resend_remaining > 0 do %>
              <span class="text-base-content/70">
                {~t"Resend code in"} {@resend_remaining}s
              </span>
            <% else %>
              <.button type="button" phx-click="resend" variant="text">
                {~t"Resend code"}
              </.button>
            <% end %>
            <.button type="button" phx-click="reset" variant="text">
              {~t"Use a different email"}
            </.button>
          </div>
        <% else %>
          <div class="space-y-2 text-center">
            <h1 class="text-xl font-semibold">{~t"Sign in"}</h1>
            <p class="text-base-content/70 text-sm">
              {~t"Continue with Google, or we'll email you a sign-in code."}
            </p>
          </div>

          <.live_component
            module={AshAuthentication.Phoenix.Components.OAuth2}
            id="sign-in-google"
            strategy={@google_strategy}
            auth_routes_prefix="/auth"
            overrides={[AshAuthentication.Phoenix.Overrides.Default]}
          />

          <div class="text-base-content/70 flex items-center gap-3 text-xs uppercase">
            <hr class="border-base-300 flex-1" />
            <span>{~t"or"}</span>
            <hr class="border-base-300 flex-1" />
          </div>

          <.form
            class="flex w-full flex-col space-y-4"
            for={@request_form}
            phx-change="change"
            phx-submit="request"
            method="POST"
          >
            <.input
              autofocus
              field={@request_form[:email]}
              label={~t"Email"}
              type="email"
              autocomplete="email"
            />

            <.button type="submit" variant="primary" size="lg">
              {~t"Send sign-in code"}
              <.icon name="hero-arrow-right" />
            </.button>
          </.form>
        <% end %>
      </section>
    </Layouts.auth>
    """
  end

  def handle_event("change", %{"user" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.request_form, params)
    {:noreply, assign(socket, request_form: form)}
  end

  def handle_event("request", %{"user" => %{"email" => email}}, socket) do
    {_result, socket} = request_code(socket, email)
    {:noreply, socket}
  end

  # The OTP itself can only be validated server-side by the sign-in action's
  # preparation, so we always hand off to Auth.AuthController and let it flash any
  # failure. Client-side `pattern`/`maxlength` cover the empty/short-code case.
  def handle_event("verify", params, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.sign_in_form, params["user"] || %{})
    {:noreply, assign(socket, sign_in_form: form, trigger_action: true)}
  end

  def handle_event("resend", _params, %{assigns: %{email: email, resend_remaining: 0}} = socket)
      when is_binary(email) do
    case request_code(socket, email) do
      {:ok, socket} -> {:noreply, put_flash(socket, :info, ~t"We've sent you a new code.")}
      {:error, socket} -> {:noreply, socket}
    end
  end

  def handle_event("resend", _params, socket), do: {:noreply, socket}

  def handle_event("reset", _params, socket) do
    {:noreply, socket |> reset_state() |> push_patch(to: ~p"/sign-in")}
  end

  def handle_info(:resend_tick, socket) do
    remaining = socket.assigns.resend_remaining - 1

    if remaining > 0 do
      Process.send_after(self(), :resend_tick, 1_000)
    end

    {:noreply, assign(socket, resend_remaining: max(remaining, 0))}
  end

  defp reset_state(%{assigns: %{strategy: strategy}} = socket) do
    assign(socket,
      email: nil,
      trigger_action: false,
      resend_remaining: 0,
      request_form: build_form(strategy, strategy.request_action_name, "otp-request"),
      sign_in_form: build_form(strategy, strategy.sign_in_action_name, "otp-sign-in")
    )
  end

  defp request_code(%{assigns: %{strategy: strategy}} = socket, email) do
    form = build_form(strategy, strategy.request_action_name, "otp-request")

    case AshPhoenix.Form.submit(form, params: %{"email" => email}) do
      {:error, form} ->
        {:error, socket |> assign(request_form: form) |> request_error_toast(form)}

      _ok ->
        Process.send_after(self(), :resend_tick, 1_000)

        socket =
          socket
          |> assign(email: email, request_form: form, resend_remaining: @resend_cooldown_seconds)
          |> push_patch(to: ~p"/sign-in?#{[email: email]}")

        {:ok, socket}
    end
  end

  defp build_form(strategy, action_name, id) do
    strategy.resource
    |> AshPhoenix.Form.for_action(action_name,
      domain: Info.authentication_domain!(strategy.resource),
      as: "user",
      id: id,
      transform_errors: fn _source, error -> error end,
      context: %{strategy: strategy, private: %{ash_authentication?: true}}
    )
    |> to_form()
  end

  defp request_error_toast(socket, form) do
    if rate_limited?(form) do
      put_flash(socket, :error, ~t"Too many requests. Please wait a few minutes and try again.")
    else
      put_flash(socket, :error, ~t"We couldn't send your sign-in code. Please try again in a moment.")
    end
  end

  defp rate_limited?(%{source: %{errors: errors}}) when is_list(errors) do
    Enum.any?(errors, &match?(%AshRateLimiter.LimitExceeded{}, &1))
  end

  defp rate_limited?(_), do: false
end
