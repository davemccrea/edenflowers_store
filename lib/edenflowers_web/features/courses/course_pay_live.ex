defmodule EdenflowersWeb.Courses.CoursePayLive do
  @moduledoc """
  The page behind a course booking's payment link, for what it still owes.
  The token in the URL is the only thing that grants access, so the page
  shows only that booking's course, seats and money.

  It always speaks the booking's language rather than the browser's.
  """
  use EdenflowersWeb, :live_view

  require Logger
  import Edenflowers.Actors

  alias Edenflowers.Courses
  alias Edenflowers.Format
  alias Edenflowers.Payments
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  def mount(%{"token" => token} = params, _session, socket) do
    case load_registration(token) do
      {:ok, registration} ->
        Localize.Plug.put_locale_from_session(
          %{Localize.Plug.PutLocale.session_key() => registration.locale},
          gettext: EdenflowersWeb.Gettext
        )

        if connected?(socket) do
          Phoenix.PubSub.subscribe(Edenflowers.PubSub, "course_registration:paid:#{registration.id}")
        end

        {:ok,
         socket
         |> assign(:page_title, ~t"Pay for your booking")
         |> assign(:locale, Format.locale())
         |> assign(:token, token)
         |> assign(:returned_from_stripe?, params["redirect_status"] == "succeeded")
         |> assign(:registration, translate_course(registration))
         |> assign_payment()
         |> maybe_flash_failed_payment(params)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, ~t"This payment link doesn't work. Please get in touch.")
         |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("pay", _params, socket) do
    with {:ok, registration} <- load_registration(socket.assigns.token),
         true <- registration.payment_link_open?,
         true <- registration.payment_intent_id == socket.assigns.registration.payment_intent_id,
         :ok <- sync_amount(registration) do
      {:noreply,
       socket
       |> assign(:registration, translate_course(registration))
       |> push_event("stripe:process_payment", %{})}
    else
      _ ->
        {:noreply,
         socket
         |> put_flash(:error, ~t"The booking changed. Please try again.")
         |> push_navigate(to: ~p"/courses/pay/#{socket.assigns.token}")}
    end
  end

  def handle_event("stripe:error", %{"message" => message, "details" => details}, socket) do
    Logger.error(
      "Stripe client error for course registration #{socket.assigns.registration.id}: #{message}: #{inspect(details)}"
    )

    {:noreply,
     put_flash(socket, :error, ~t"Payment is temporarily unavailable. Please refresh the page and try again.")}
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: "course_registration:paid:" <> _}, socket) do
    {:ok, registration} = load_registration(socket.assigns.token)
    {:noreply, socket |> assign(:registration, translate_course(registration)) |> assign(:client_secret, nil)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} order={@order} flash={@flash} current_path={@current_path}>
      <.container>
        <div class="max-w-xl">
          <.flower name="flower-30" class="text-primary/70 mb-8 h-16 w-16" />

          <%= cond do %>
            <% @registration.status == :cancelled -> %>
              <h1 class="page-title mb-6">{~t"Booking cancelled"}</h1>
              <p class="leading-relaxed" data-testid="pay-cancelled">
                {~t"This booking has been cancelled, so there is nothing to pay. Get in touch if that's a surprise."}
              </p>
            <% not @registration.payment_link_open? -> %>
              <h1 class="page-title mb-6">{~t"Thank you"}</h1>
              <p class="leading-relaxed" data-testid="pay-paid">
                {~t"This booking is paid. Thank you!"}
              </p>
            <% @returned_from_stripe? -> %>
              <h1 class="page-title mb-6">{~t"Thank you"}</h1>
              <p role="status" class="leading-relaxed" data-testid="pay-confirming">
                {~t"Confirming your payment… You'll get a receipt by email once it's done."}
              </p>
            <% true -> %>
              <h1 class="page-title mb-6">{~t"Pay for your booking"}</h1>
          <% end %>

          <dl class="border-base-content/12 grid-cols-[auto_1fr] mt-10 grid items-baseline gap-x-6 gap-y-3 border-y py-6">
            <dt class="eyebrow text-base-content/70">{~t"Course"}</dt>
            <dd>{@registration.course.name}</dd>

            <dt class="eyebrow text-base-content/70">{~t"When"}</dt>
            <dd class="tabular-nums">
              {Format.weekday_date(@registration.course.date, @locale)}, {Format.time(
                @registration.course.start_time,
                @locale
              )}–{Format.time(@registration.course.end_time, @locale)}
            </dd>

            <dt class="eyebrow text-base-content/70">{~t"Places"}</dt>
            <dd class="tabular-nums">{@registration.seats_held}</dd>

            <dt class="eyebrow text-base-content/70">{~t"Total"}</dt>
            <dd class="tabular-nums" data-testid="pay-total">{Format.currency(@registration.total_due, @locale)}</dd>

            <%= if Decimal.positive?(@registration.amount_paid) do %>
              <dt class="eyebrow text-base-content/70">{~t"Paid so far"}</dt>
              <dd class="tabular-nums">{Format.currency(@registration.amount_paid, @locale)}</dd>
            <% end %>

            <%= if @registration.payment_link_open? do %>
              <dt class="eyebrow text-base-content/70">{~t"Left to pay"}</dt>
              <dd class="font-semibold tabular-nums" data-testid="pay-balance">
                {Format.currency(@registration.balance, @locale)}
              </dd>
            <% end %>
          </dl>

          <section
            :if={@registration.payment_link_open? and not @returned_from_stripe?}
            class="mt-10"
            aria-label={~t"Payment"}
          >
            <.stripe_form
              :if={@client_secret}
              id="pay-form"
              phx-submit="pay"
              client_secret={@client_secret}
              return_url={url(~p"/courses/pay/#{@token}")}
              billing_name={@registration.name}
              billing_email={@registration.email}
            >
              {~t"Pay"} {Format.currency(@registration.balance, @locale)}
            </.stripe_form>

            <p :if={@payment_unavailable?} class="text-error" data-testid="stripe-unavailable">
              {~t"Payment is temporarily unavailable. Please try again in a moment."}
            </p>
          </section>
        </div>
      </.container>
    </Layouts.app>
    """
  end

  defp load_registration(token), do: Courses.get_registration_by_payment_link_token(token, actor: system_actor())

  defp translate_course(registration), do: Map.update!(registration, :course, &Translations.translate/1)

  # Stripe is only touched once the page is live, so a crawler or a link
  # preview never creates a PaymentIntent. Back from Stripe, the payment is
  # in flight and its PaymentIntent must not change.
  defp assign_payment(%{assigns: %{registration: registration}} = socket) do
    if connected?(socket) and registration.payment_link_open? and not socket.assigns.returned_from_stripe? do
      case client_secret(registration) do
        {:ok, client_secret} ->
          assign(socket, client_secret: client_secret, payment_unavailable?: false)

        {:error, reason} ->
          Logger.error("Could not set up payment for course registration #{registration.id}: #{inspect(reason)}")
          assign(socket, client_secret: nil, payment_unavailable?: true)
      end
    else
      assign(socket, client_secret: nil, payment_unavailable?: false)
    end
  end

  # A seat removed since the PaymentIntent was made changes what's owed.
  defp client_secret(registration) do
    with :ok <- sync_amount(registration),
         {:ok, _registration, client_secret} <- Payments.setup(registration, system_actor()) do
      {:ok, client_secret}
    end
  end

  defp sync_amount(%{payment_intent_id: nil}), do: :ok

  defp sync_amount(registration) do
    case Payments.update_amount(registration) do
      {:ok, _payment_intent} -> :ok
      error -> error
    end
  end

  # A redirect-based method (MobilePay) comes back with `redirect_status=failed`
  # when the customer cancels or is declined in the app.
  defp maybe_flash_failed_payment(socket, %{"redirect_status" => "failed"}) do
    put_flash(socket, :error, ~t"Your payment didn't go through. Please try again or choose another payment method.")
  end

  defp maybe_flash_failed_payment(socket, _params), do: socket
end
