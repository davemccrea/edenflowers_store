defmodule EdenflowersWeb.NewsletterSignupForm do
  use EdenflowersWeb, :live_component

  def mount(socket) do
    {:ok, assign(socket, form: to_form(%{"email_address" => ""}))}
  end

  def render(assigns) do
    ~H"""
    <section class="space-y-4">
      <div>
        <h1 class="font-serif text-2xl sm:text-3xl">
          {gettext("Sign up and enjoy 15% off your next order.")}
        </h1>

        <p class="font-sans text-sm">
          {gettext("We don't like spam and will only send emails a few times per year.")}
        </p>
      </div>

      <.form id="newsletter-form" for={@form} phx-target={@myself} phx-submit="submit">
        <div class="join w-full">
          <.input
            field={@form[:email_address]}
            type="email"
            class="input join-item"
            placeholder={gettext("Email Address")}
          />
          <button class="btn join-item">{gettext("Subscribe")}</button>
        </div>
      </.form>
    </section>
    """
  end

  def handle_event("submit", %{"email_address" => email_address} = params, socket) do
    socket = assign(socket, form: to_form(params))

    case Edenflowers.Accounts.User.subscribe_to_newsletter(email_address, authorize?: false) do
      {:ok, _} ->
        toast = EdenflowersWeb.LiveToast.new(:info, gettext("You've been subscribed to the newsletter 🥳."))

        {:noreply,
         socket
         |> assign(form: to_form(%{"email_address" => ""}))
         |> push_event("toast:show", toast)}

      {:error, _} ->
        toast = EdenflowersWeb.LiveToast.new(:error, gettext("There was an error subscribing to the newsletter."))
        {:noreply, push_event(socket, "toast:show", toast)}
    end
  end
end
