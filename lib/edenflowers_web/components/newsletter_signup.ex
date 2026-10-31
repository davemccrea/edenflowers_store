defmodule EdenflowersWeb.NewsletterSignup do
  @moduledoc """
  Newsletter signup form that records the address and starts the welcome promotion flow.
  """

  use EdenflowersWeb, :live_component
  require Logger

  @impl true
  def mount(socket) do
    {:ok, assign(socket, submitted: false, error: nil)}
  end

  @impl true
  def update(assigns, socket) do
    # Only the first render takes the pre-filled address, so a later parent
    # re-render can't overwrite what the visitor submitted.
    {:ok, assign_new(socket, :form, fn -> to_form(%{"email_address" => assigns.email || ""}) end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="max-w-md space-y-5">
      <h2 class="eyebrow text-link-underline">{~t"Newsletter"}</h2>

      <p class="font-serif text-2xl leading-snug tracking-tight md:text-3xl">
        {~t"Get 15% off your first order."}
      </p>

      <%= if @submitted do %>
        <%!-- hero-reveal replays here because the element enters the DOM on submit. --%>
        <p class="hero-reveal opacity-80">
          {~t"Thanks! Your 15% off code is on its way to your inbox."}
        </p>
      <% else %>
        <.form id="newsletter-form" for={@form} phx-target={@myself} phx-submit="submit" class="space-y-4">
          <label for="newsletter-form_email_address" class="sr-only">
            {~t"Email Address"}
          </label>
          <%!-- Keyboard focus thickens the rule instead of boxing the input: a
                ring around a borderless field would cut across the underline
                and the Subscribe button. The shadow fakes the second pixel so
                nothing below shifts. --%>
          <div class="border-current/30 flex items-center gap-2 border-b pb-1 transition-colors has-[:focus-visible]:shadow-[0_1px_0_0_currentColor] focus-within:border-current">
            <input
              type="email"
              name="email_address"
              id="newsletter-form_email_address"
              value={Phoenix.HTML.Form.input_value(@form, :email_address)}
              class="flex-1 border-0 bg-transparent px-0 py-2 text-base pointer-coarse:py-2.5 placeholder:text-current/70 focus-visible:outline-hidden"
              placeholder={~t"your@email.com"}
              autocomplete="email"
              required
            />
            <button
              type="submit"
              aria-label={~t"Subscribe"}
              class="touch-target group flex flex-none p-1 opacity-70 transition-opacity hover:opacity-100"
            >
              <.icon
                name="hero-arrow-right"
                class="h-5 w-5 transition-transform duration-300 ease-out group-hover:translate-x-1"
              />
            </button>
          </div>
          <%!-- Inline rather than a flash: a component's flash only reaches the
                page on navigation, so it would never show here. --%>
          <p :if={@error == :invalid_email} role="alert" class="text-link-underline text-sm">
            {~t"Enter a valid email address."}
          </p>
          <p :if={@error == :failed} role="alert" class="text-link-underline text-sm">
            {~t"There was an error subscribing to the newsletter."}
          </p>
          <p class="text-xs leading-relaxed opacity-80">
            {~t"Only occasional emails. Unsubscribe at any time."}
            <a class="link-underline-static-body" href={~q"/#{language}/privacy"}>
              {~t"Privacy policy"}
            </a>
          </p>
        </.form>
      <% end %>
    </section>
    """
  end

  @impl true
  def handle_event("submit", %{"email_address" => email_address} = params, socket) do
    socket = assign(socket, form: to_form(params))

    locale = to_string(Edenflowers.Format.locale())

    case Edenflowers.Accounts.subscribe_to_newsletter(email_address, locale) do
      {:ok, _} ->
        {:noreply, socket |> assign(submitted: true) |> EdenflowersWeb.Analytics.track("Newsletter signup")}

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        if Enum.any?(errors, &(Map.get(&1, :field) == :email)) do
          {:noreply, assign(socket, error: :invalid_email)}
        else
          failed(socket, error)
        end

      {:error, error} ->
        failed(socket, error)
    end
  end

  defp failed(socket, error) do
    Logger.error(inspect(error))
    {:noreply, assign(socket, error: :failed)}
  end
end
