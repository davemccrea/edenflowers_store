defmodule EdenflowersWeb.NewsletterSignupForm do
  use EdenflowersWeb, :live_component
  require Logger

  def mount(socket) do
    {:ok, assign(socket, form: to_form(%{"email_address" => ""}), submitted: false)}
  end

  def render(assigns) do
    ~H"""
    <section class="max-w-md space-y-5">
      <h3 class="eyebrow text-base-content/60">{~t"Newsletter"}</h3>

      <p class="font-serif text-2xl leading-snug tracking-tight md:text-3xl">
        {~t"Get 15% off your first order."}
      </p>

      <%= if @submitted do %>
        <p class="text-base-content/80">
          {~t"Thanks! Your 15% off code is on its way to your inbox."}
        </p>
      <% else %>
        <.form id="newsletter-form" for={@form} phx-target={@myself} phx-submit="submit" class="space-y-4">
          <label for="newsletter-form_email_address" class="sr-only">
            {~t"Email Address"}
          </label>
          <div class="border-base-content/30 flex items-baseline gap-4 border-b pb-1 transition-colors focus-within:border-base-content">
            <input
              type="email"
              name="email_address"
              id="newsletter-form_email_address"
              value={Phoenix.HTML.Form.input_value(@form, :email_address)}
              class="flex-1 border-0 bg-transparent px-0 py-2 text-base placeholder:text-base-content/40 focus:outline-none focus:ring-0"
              placeholder={~t"your@email.com"}
              autocomplete="email"
            />
            <button
              type="submit"
              class="eyebrow text-base-content/70 link-underline-hover-nav whitespace-nowrap py-2 hover:text-base-content"
            >
              {~t"Subscribe"}
            </button>
          </div>
          <p class="text-base-content/60 text-xs leading-relaxed">
            {~t"Only occasional emails — unsubscribe at any time."}
          </p>
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
        {:noreply, put_flash(socket, :error, ~t"There was an error subscribing to the newsletter.")}
    end
  end
end
