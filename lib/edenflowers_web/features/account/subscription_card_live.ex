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

  @impl true
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
          |> assign(:payment_unavailable?, false)

        if connected?(socket),
          do: {:ok, back_from_stripe(socket, params)},
          else: {:ok, socket}

      _not_found_or_cancelled ->
        {:ok,
         socket |> put_flash(:error, ~t"Your subscription couldn't be changed.") |> push_navigate(to: ~p"/account")}
    end
  end

  @impl true
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
          <.stripe_form
            id="card-form"
            phx-submit="save_card"
            mode="setup"
            return_path={~p"/account/subscriptions/#{@subscription.id}/card"}
            billing_name={@current_user.name}
            billing_email={to_string(@current_user.email)}
          >
            {~t"Save card"}
          </.stripe_form>

          <div :if={@payment_unavailable?} data-testid="stripe-unavailable">
            <p class="text-error">{~t"Payment is temporarily unavailable. Please try again in a moment."}</p>
            <p class="mt-2">
              {~t"Your current card stays in place until you save a new one. If this keeps happening,"}
              <.link navigate={~q"/#{language}/contact"} class="link-underline-hover text-primary">{~t"contact us"}</.link>.
            </p>
          </div>
        </section>

        <.button navigate={~p"/account"} variant="text" class="mt-6">{~t"Back to your account"}</.button>
      </.container>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save_card", _params, socket) do
    case Payments.setup_card_replacement(socket.assigns.subscription) do
      {:ok, client_secret} ->
        {:noreply,
         socket
         |> assign(:payment_unavailable?, false)
         |> push_event("stripe:process_payment", %{client_secret: client_secret})}

      {:error, reason} ->
        Logger.error("Could not set up a card for subscription #{socket.assigns.subscription.id}: #{inspect(reason)}")
        {:noreply, socket |> assign(:payment_unavailable?, true) |> push_event("stripe:ready", %{})}
    end
  end

  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error(
      "Stripe client error for subscription #{socket.assigns.subscription.id}: #{message}: #{inspect(details)}"
    )

    {:noreply,
     put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please refresh the page and try again.")}
  end

  defp back_from_stripe(socket, %{"setup_intent" => setup_intent_id, "redirect_status" => "succeeded"}) do
    save_card(socket, setup_intent_id)
  end

  defp back_from_stripe(socket, %{"redirect_status" => "failed"}) do
    put_flash(socket, :error, ~t"Your card couldn't be saved. Please try again or use another card.")
  end

  defp back_from_stripe(socket, _params), do: socket

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
    end
  end
end
