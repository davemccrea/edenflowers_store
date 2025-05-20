defmodule EdenflowersWeb.NewsletterSignupForm do
  use EdenflowersWeb, :live_component

  def render(assigns) do
    ~H"""
    <section>
      <h1 class="font-serif text-2xl sm:text-3xl">
        {gettext("Enjoy 20% off your next order and get occassional floral advice in your inbox.")}
      </h1>

      <.form for={to_form(%{})} phx-submit="submit" phx-target={@myself}>
        <input type="text" class="input input-lg w-full text-sm" placeholder="Email Address" name="email_address" />
      </.form>
    </section>
    """
  end

  def handle_event("submit", %{"email_address" => email_address}, socket) do
    socket =
      case Edenflowers.Accounts.User.subscribe_to_newsletter(email_address, authorize?: false) do
        {:ok, _} ->
          toast = EdenflowersWeb.LiveToast.new(:info, gettext("You've been subscribed to the newsletter 🥳."))
          push_event(socket, "toast:show", toast)

        {:error, _} ->
          toast = EdenflowersWeb.LiveToast.new(:error, gettext("There was an error subscribing to the newsletter."))
          push_event(socket, "toast:show", toast)
      end

    {:noreply, socket}
  end
end
