defmodule EdenflowersWeb.NewsletterSignupForm do
  use EdenflowersWeb, :live_component

  def mount(socket) do
    {:ok, assign(socket, form: to_form(%{"email_address" => ""}))}
  end

  def render(assigns) do
    ~H"""
    <section class="space-y-2">
      <h1 class="font-serif text-2xl sm:text-3xl">
        {gettext("Register and enjoy 15% off your next order.")}
      </h1>

      <.form id="newsletter-form" for={@form} phx-target={@myself} phx-submit="submit">
        <div class="join w-full">
          <input
            type="email"
            name="email_address"
            id="newsletter-form_email_address"
            value={Phoenix.HTML.Form.input_value(@form, :email_address)}
            class="input join-item w-full"
            placeholder={gettext("Email Address")}
          />

          <button class="btn btn-primary join-item">{gettext("Register")}</button>
        </div>
      </.form>

      <p class="font-sans text-xs">
        {gettext("We send out only ocassional emails. Unsubscribe at any time.")}
      </p>
    </section>
    """
  end

  def handle_event("submit", %{"email_address" => email_address} = params, socket) do
    socket = assign(socket, form: to_form(params))

    case Edenflowers.Accounts.User.subscribe_to_newsletter(email_address) do
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
