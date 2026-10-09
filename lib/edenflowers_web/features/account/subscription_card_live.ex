defmodule EdenflowersWeb.Account.SubscriptionCardLive do
  @moduledoc """
  Replaces the card a subscription charges, through a Stripe SetupIntent and
  the same Payment Element checkout uses. Stripe returns here once the card is
  saved, and the card is stored straight away; the `setup_intent.succeeded`
  webhook stores it too, in case the customer never comes back.
  """
  use EdenflowersWeb, :live_view

  require Logger

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Payments
  alias EdenflowersWeb.Checkout.Fields

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_required}

  defp stripe_publishable_key, do: Application.get_env(:edenflowers, :stripe_publishable_key)

  def mount(%{"id" => id} = params, _session, socket) do
    user = socket.assigns.current_user

    case Orders.get_subscription(id, actor: user) do
      {:ok, %{state: state} = subscription} when state != :cancelled ->
        # `replace_card` settles nothing already owed, so the unpaid Occurrence
        # still needs its payment link, even once the new card restarts it.
        unpaid = Subscription.unpaid_occurrence(Orders.list_my_orders!(actor: user), subscription)

        socket =
          socket
          |> assign(:page_title, ~t"Update your card")
          |> assign(:subscription, subscription)
          |> assign(:unpaid, unpaid)

        # Stripe is only touched once the page is live, so a link preview or
        # the static first render never calls it.
        if connected?(socket),
          do: {:ok, set_up_card(socket, params)},
          else: {:ok, assign(socket, client_secret: nil, payment_unavailable?: false)}

      _not_found_or_cancelled ->
        {:ok,
         socket |> put_flash(:error, ~t"Your subscription couldn't be changed.") |> push_navigate(to: ~p"/account")}
    end
  end

  def handle_event("save_card", _params, socket) do
    {:noreply, push_event(socket, "stripe:process_payment", %{})}
  end

  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error(
      "Stripe client error for subscription #{socket.assigns.subscription.id}: #{message}: #{inspect(details)}"
    )

    {:noreply,
     put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please refresh the page and try again.")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container class="max-w-xl">
        <h1 class="page-title mb-6">{~t"Update your card"}</h1>
        <p class="leading-relaxed">
          {~t"Every delivery from now on is charged to the card you save here."}
        </p>
        <p :if={Fields.card_label(@subscription)} class="mt-4 leading-relaxed" data-testid="current-card">
          {~t"Your deliveries are charged to #{card = Fields.card_label(@subscription)} at the moment."}
        </p>
        <p :if={@unpaid} class="mt-4 leading-relaxed" data-testid="unpaid-occurrence">
          {~t"Your delivery on #{date = Edenflowers.Format.date(@unpaid.fulfillment_date, Edenflowers.Format.locale())} is still unpaid, and a new card doesn't pay it."}
          <.link navigate={~p"/pay/#{@unpaid.payment_link_token}"} class="link-underline-hover text-primary">
            {~t"Pay now"}
          </.link>
        </p>

        <section class="mt-10" aria-label={~t"Card"}>
          <form
            :if={@client_secret}
            id="card-form"
            phx-hook="Stripe"
            phx-submit="save_card"
            data-intent="setup"
            data-client-secret={@client_secret}
            data-publishable-key={stripe_publishable_key()}
            data-return-url={url(~p"/account/subscriptions/#{@subscription.id}/card")}
            data-billing-name={@current_user.name}
            data-billing-email={to_string(@current_user.email)}
            data-stripe-loading={JS.set_attribute({"disabled", "true"}, to: "#payment-button")}
            data-stripe-ready={JS.remove_attribute("disabled", to: "#payment-button")}
            class="flex flex-col gap-4"
          >
            <div phx-update="ignore" id="payment-element"></div>
            <p phx-update="ignore" id="stripe-error-message" role="alert" class="text-error"></p>

            <.form_button disabled={true} id="payment-button">{~t"Save card"}</.form_button>
          </form>

          <div :if={@payment_unavailable?} data-testid="stripe-unavailable">
            <p class="text-error">{~t"Payment is temporarily unavailable. Please try again in a moment."}</p>
            <p class="mt-2">
              {~t"Your current card stays in place until you save a new one. If this keeps happening,"}
              <.link navigate={~p"/contact"} class="link-underline-hover text-primary">{~t"contact us"}</.link>.
            </p>
          </div>
        </section>

        <.button navigate={~p"/account"} variant="text" class="mt-6">{~t"Back to your account"}</.button>
      </.container>
    </Layouts.app>
    """
  end

  defp set_up_card(socket, %{"setup_intent" => setup_intent_id, "redirect_status" => "succeeded"}) do
    save_card(socket, setup_intent_id)
  end

  defp set_up_card(socket, %{"redirect_status" => "failed"}) do
    socket
    |> put_flash(:error, ~t"Your card couldn't be saved. Please try again or use another card.")
    |> assign_setup_intent()
  end

  defp set_up_card(socket, _params), do: assign_setup_intent(socket)

  defp assign_setup_intent(socket) do
    case Payments.setup_card_replacement(socket.assigns.subscription) do
      {:ok, client_secret} ->
        assign(socket, client_secret: client_secret, payment_unavailable?: false)

      {:error, reason} ->
        Logger.error("Could not set up a card for subscription #{socket.assigns.subscription.id}: #{inspect(reason)}")
        assign(socket, client_secret: nil, payment_unavailable?: true)
    end
  end

  defp save_card(socket, setup_intent_id) do
    %{subscription: subscription, current_user: user} = socket.assigns

    case Payments.save_subscription_card(setup_intent_id, user) do
      {:ok, _subscription} ->
        socket
        |> put_flash(:info, ~t"Your card has been updated.")
        |> push_navigate(to: ~p"/account")

      error ->
        Logger.error("Could not save the card for subscription #{subscription.id}: #{inspect(error)}")

        socket
        |> put_flash(:error, ~t"Your card couldn't be saved. Please try again or use another card.")
        |> assign_setup_intent()
    end
  end
end
