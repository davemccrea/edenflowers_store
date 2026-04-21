defmodule EdenflowersWeb.NewsletterSignupForm do
  use EdenflowersWeb, :live_component
  require Logger

  def mount(socket) do
    {:ok, assign(socket, form: to_form(%{"email_address" => ""}), submitted: false)}
  end

  def render(assigns) do
    ~H"""
    <section class="space-y-4">
      <h1 class="section-title">
        {~t"Register and enjoy 15% off your next order."}
      </h1>

      <%= if @submitted do %>
        <p>{~t"Thanks! We've sent your 15% off code to your inbox."}</p>
      <% else %>
        <.form id="newsletter-form" for={@form} phx-target={@myself} phx-submit="submit">
          <label for="newsletter-form_email_address" class="sr-only">
            {~t"Email Address"}
          </label>
          <div class="space-y-2">
            <div class="relative max-w-sm">
              <input
                type="email"
                name="email_address"
                id="newsletter-form_email_address"
                value={Phoenix.HTML.Form.input_value(@form, :email_address)}
                class="input input-lg w-full pr-12"
                placeholder={~t"Your email"}
              />
              <button type="submit" class="absolute inset-y-0 right-3 z-10 flex items-center text-base-content/50 hover:text-base-content transition cursor-pointer" aria-label={~t"Register"}>
                <.icon name="hero-paper-airplane" class="h-5 w-5" />
              </button>
            </div>
            <p class="font-sans text-xs text-base-content/60">
              {~t"We send out only ocassional emails. Unsubscribe at any time."}
            </p>
          </div>
        </.form>
      <% end %>
    </section>
    """
  end

  def handle_event("submit", %{"email_address" => email_address} = params, socket) do
    socket = assign(socket, form: to_form(params))

    case Edenflowers.Accounts.User.subscribe_to_newsletter(email_address) do
      {:ok, _} ->
        locale = Gettext.get_locale(EdenflowersWeb.Gettext)

        Edenflowers.Workers.SendNewsletterPromoEmail.enqueue(%{"email" => email_address, "locale" => locale})
        {:noreply, assign(socket, submitted: true)}

      {:error, error} ->
        Logger.error(inspect(error))
        toast = EdenflowersWeb.LiveToast.new(:error, ~t"There was an error subscribing to the newsletter.")
        {:noreply, push_event(socket, "toast:show", toast)}
    end
  end
end
